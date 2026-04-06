#!/usr/bin/env bash
# ddto_multi_auto.sh — D.D.T.O. multi-repo runner with GitHub API auto-discovery
#
# Discovers all repositories for $GITHUB_USER via the GitHub API, then clones
# or updates each one and runs the full D.D.T.O. protocol (ddto_stars.sh).
#
# Required environment variables:
#   GITHUB_USER   — GitHub username
#   GITHUB_TOKEN  — Personal access token with 'repo' scope
#
# Optional environment variables:
#   DDTO_WORKDIR  — Directory to clone repositories into (default: ./ddto-workspace)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
WORKDIR="${DDTO_WORKDIR:-${SCRIPT_DIR}/ddto-workspace}"
HEALTH_REPORT="${SCRIPT_DIR}/ddto-health-${TIMESTAMP}.md"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()     { echo "[multi-auto] $*"; }
log_ok()  { echo "[multi-auto] ✔  $*"; }
log_err() { echo "[multi-auto] ✘  $*" >&2; }

require_env() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    log_err "Environment variable '${var}' is not set."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Validate environment
# ---------------------------------------------------------------------------

require_env GITHUB_USER
require_env GITHUB_TOKEN

mkdir -p "${WORKDIR}"

# ---------------------------------------------------------------------------
# Discover all repositories via GitHub API
# ---------------------------------------------------------------------------

log "Discovering repositories for user: ${GITHUB_USER}"

repos=()
page=1
while true; do
  response="$(curl -fsSL \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/user/repos?per_page=100&page=${page}")"

  # Use jq for reliable JSON parsing when available; fall back to grep/sed
  batch_names=()
  batch_urls=()
  if command -v jq &>/dev/null; then
    while IFS= read -r line; do
      batch_names+=("${line}")
    done < <(echo "${response}" | jq -r '.[].full_name' 2>/dev/null || true)
    while IFS= read -r line; do
      batch_urls+=("${line}")
    done < <(echo "${response}" | jq -r '.[].clone_url' 2>/dev/null || true)
  else
    while IFS= read -r line; do
      batch_names+=("${line}")
    done < <(echo "${response}" | grep '"full_name"' | sed 's/.*"full_name": "\([^"]*\)".*/\1/')
    while IFS= read -r line; do
      batch_urls+=("${line}")
    done < <(echo "${response}" | grep '"clone_url"' | sed 's/.*"clone_url": "\([^"]*\)".*/\1/')
  fi

  if [[ "${#batch_names[@]}" -eq 0 ]]; then
    break
  fi

  for i in "${!batch_names[@]}"; do
    repos+=("${batch_names[$i]}|${batch_urls[$i]:-}")
  done

  (( page++ ))
done

log_ok "Discovered ${#repos[@]} repositories."

if [[ "${#repos[@]}" -eq 0 ]]; then
  log "No repositories found. Exiting."
  exit 0
fi

# ---------------------------------------------------------------------------
# Set up a temporary git credential store (avoids token in process list)
# ---------------------------------------------------------------------------

GIT_CRED_FILE="$(mktemp)"
chmod 600 "${GIT_CRED_FILE}"
echo "https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com" > "${GIT_CRED_FILE}"
trap 'rm -f "${GIT_CRED_FILE}"' EXIT

# ---------------------------------------------------------------------------
# Clone or update each repository, then run the D.D.T.O. protocol
# ---------------------------------------------------------------------------

PASS=0
FAIL=0
SKIPPED=0

{
  echo "# D.D.T.O. Multi-Repo Health Report"
  echo ""
  echo "**User:**      ${GITHUB_USER}"
  echo "**Timestamp:** ${TIMESTAMP}"
  echo "**Total repos discovered:** ${#repos[@]}"
  echo ""
  echo "| Repository | Status | Notes |"
  echo "|-----------|--------|-------|"
} > "${HEALTH_REPORT}"

for entry in "${repos[@]}"; do
  full_name="${entry%%|*}"
  clone_url="${entry##*|}"
  repo_name="${full_name##*/}"
  repo_dir="${WORKDIR}/${repo_name}"

  log "Processing: ${full_name}"

  # Clone or update using the temporary credential store
  if [[ -d "${repo_dir}/.git" ]]; then
    log "  Updating existing clone: ${repo_dir}"
    git -C "${repo_dir}" -c "credential.helper=store --file=${GIT_CRED_FILE}" fetch --all --prune -q 2>/dev/null || true
    git -C "${repo_dir}" pull -q --ff-only 2>/dev/null || \
      git -C "${repo_dir}" pull -q --rebase 2>/dev/null || true
  else
    log "  Cloning: ${clone_url}"
    git -c "credential.helper=store --file=${GIT_CRED_FILE}" clone -q "${clone_url}" "${repo_dir}" 2>/dev/null || {
      log_err "  Failed to clone ${full_name}; skipping."
      echo "| ${full_name} | ⚠️ SKIPPED | Clone failed |" >> "${HEALTH_REPORT}"
      (( SKIPPED++ )) || true
      continue
    }
  fi

  # Run the D.D.T.O. protocol
  if ( cd "${repo_dir}" && bash "${SCRIPT_DIR}/ddto_stars.sh" ); then
    log_ok "  Protocol complete: ${full_name}"
    echo "| ${full_name} | ✅ PASS | |" >> "${HEALTH_REPORT}"
    (( PASS++ )) || true
  else
    log_err "  Protocol failed: ${full_name}"
    echo "| ${full_name} | ❌ FAIL | See ${repo_dir}/ddto.log |" >> "${HEALTH_REPORT}"
    (( FAIL++ )) || true
  fi
done

# ---------------------------------------------------------------------------
# Consolidated health summary
# ---------------------------------------------------------------------------

{
  echo ""
  echo "## Summary"
  echo ""
  echo "- **Pass:**    ${PASS}"
  echo "- **Fail:**    ${FAIL}"
  echo "- **Skipped:** ${SKIPPED}"
} >> "${HEALTH_REPORT}"

log "=== Multi-repo run complete ==="
log "  Pass:    ${PASS}"
log "  Fail:    ${FAIL}"
log "  Skipped: ${SKIPPED}"
log "  Health report: ${HEALTH_REPORT}"
