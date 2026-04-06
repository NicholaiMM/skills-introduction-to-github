#!/usr/bin/env bash
# sevenstars.sh — D.D.T.O. Seven Stars Toolkit
# Unified automated workflow for repository hygiene.
#
# Usage:
#   sevenstars.sh repo          Run D.D.T.O. protocol on the current repository
#   sevenstars.sh all           Auto-discover and process all repositories for $GITHUB_USER
#   sevenstars.sh dashboard     Create a local HTML dashboard (ddto_dashboard.html)
#   sevenstars.sh constellation Build a GitHub Pages constellation map (index.html)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------

log() { echo "[sevenstars] $*"; }

require_env() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: Environment variable '$var' is not set." >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Command: repo — run the D.D.T.O. protocol on the current repository
# ---------------------------------------------------------------------------

cmd_repo() {
  log "Running D.D.T.O. protocol on current repository..."
  bash "${SCRIPT_DIR}/ddto_stars.sh"
}

# ---------------------------------------------------------------------------
# Command: all — auto-discover repos and run the protocol on each
# ---------------------------------------------------------------------------

cmd_all() {
  require_env GITHUB_USER
  require_env GITHUB_TOKEN

  log "Auto-discovering repositories for user: ${GITHUB_USER}"
  bash "${SCRIPT_DIR}/ddto_multi_auto.sh"
}

# ---------------------------------------------------------------------------
# Command: dashboard — create ddto_dashboard.html in the current directory
# ---------------------------------------------------------------------------

cmd_dashboard() {
  local summary_file="ddto_summary.md"
  local output_file="ddto_dashboard.html"

  log "Generating dashboard: ${output_file}"

  local summary_content=""
  if [[ -f "${summary_file}" ]]; then
    summary_content="$(cat "${summary_file}")"
  else
    summary_content="No summary file found. Run \`sevenstars.sh repo\` first."
  fi

  cat > "${output_file}" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>D.D.T.O. Dashboard — $(basename "$(pwd)")</title>
  <style>
    body { font-family: sans-serif; max-width: 900px; margin: 2em auto; padding: 0 1em; background: #0d1117; color: #c9d1d9; }
    h1   { color: #58a6ff; }
    pre  { background: #161b22; padding: 1em; border-radius: 6px; overflow-x: auto; white-space: pre-wrap; }
    .meta { color: #8b949e; font-size: 0.85em; margin-bottom: 1em; }
  </style>
</head>
<body>
  <h1>&#11088; D.D.T.O. Dashboard</h1>
  <p class="meta">Repository: <strong>$(basename "$(pwd)")</strong> &nbsp;|&nbsp; Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')</p>
  <pre>${summary_content}</pre>
</body>
</html>
HTML

  log "Dashboard written to ${output_file}"
}

# ---------------------------------------------------------------------------
# Command: constellation — build a GitHub Pages constellation map (index.html)
# ---------------------------------------------------------------------------

cmd_constellation() {
  require_env GITHUB_USER
  require_env GITHUB_TOKEN

  log "Building constellation map for user: ${GITHUB_USER}"

  local page=1
  local repos=()
  while true; do
    local batch
    batch="$(curl -fsSL \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/user/repos?per_page=100&page=${page}")"

    # Use jq for reliable JSON parsing when available; fall back to grep/sed
    local batch_repos=()
    if command -v jq &>/dev/null; then
      while IFS= read -r name; do
        batch_repos+=("${name}")
      done < <(echo "${batch}" | jq -r '.[].full_name' 2>/dev/null || true)
    else
      while IFS= read -r name; do
        batch_repos+=("${name}")
      done < <(echo "${batch}" | grep '"full_name"' | sed 's/.*"full_name": "\([^"]*\)".*/\1/')
    fi

    [[ "${#batch_repos[@]}" -eq 0 ]] && break
    repos+=("${batch_repos[@]}")
    (( page++ ))
  done

  log "Found ${#repos[@]} repositories."

  local links=""
  for repo in "${repos[@]}"; do
    local repo_name="${repo##*/}"
    links+="    <li><a href=\"https://${GITHUB_USER}.github.io/${repo_name}/ddto_dashboard.html\">&#11088; ${repo}</a></li>\n"
  done

  cat > "index.html" <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>D.D.T.O. Constellation — ${GITHUB_USER}</title>
  <style>
    body { font-family: sans-serif; max-width: 900px; margin: 2em auto; padding: 0 1em; background: #0d1117; color: #c9d1d9; }
    h1   { color: #58a6ff; }
    ul   { list-style: none; padding: 0; }
    li   { margin: 0.4em 0; }
    a    { color: #79c0ff; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .meta { color: #8b949e; font-size: 0.85em; }
  </style>
</head>
<body>
  <h1>&#11088; D.D.T.O. Constellation Map</h1>
  <p class="meta">User: <strong>${GITHUB_USER}</strong> &nbsp;|&nbsp; Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')</p>
  <ul>
$(printf '%s' "${links}")  </ul>
</body>
</html>
HTML

  log "Constellation map written to index.html"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

case "${1:-}" in
  repo)          cmd_repo ;;
  all)           cmd_all ;;
  dashboard)     cmd_dashboard ;;
  constellation) cmd_constellation ;;
  *)
    echo "Usage: $0 {repo|all|dashboard|constellation}" >&2
    exit 1
    ;;
esac
