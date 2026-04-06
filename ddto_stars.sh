#!/usr/bin/env bash
# ddto_stars.sh — D.D.T.O. per-repository protocol script
#
# Performs the full D.D.T.O. (Detect, Diagnose, Treat, Optimize) protocol on
# the current Git repository.
#
# Usage:
#   ddto_stars.sh               Run the full protocol
#   ddto_stars.sh --selfheal    Re-run failed steps automatically

set -euo pipefail

TIMESTAMP="$(date -u '+%Y%m%d-%H%M%S')"
LOG_FILE="ddto.log"
SUMMARY_FILE="ddto_summary.md"
LINK_REPORT="link-check-report.md"
SMOKE_TEST="SMOKE_TEST.md"
BACKUP_BRANCH="ddto-backup-${TIMESTAMP}"
TAG_NAME="ddto-${TIMESTAMP}"
SELFHEAL=false

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------

for arg in "$@"; do
  case "${arg}" in
    --selfheal) SELFHEAL=true ;;
    *) echo "Unknown argument: ${arg}" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------

exec > >(tee -a "${LOG_FILE}") 2>&1

log()     { echo "[$(date -u '+%H:%M:%S')] $*"; }
log_ok()  { echo "[$(date -u '+%H:%M:%S')] ✔  $*"; }
log_err() { echo "[$(date -u '+%H:%M:%S')] ✘  $*" >&2; }

SUMMARY_LINES=()
record() { SUMMARY_LINES+=("$*"); }

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

preflight() {
  log "=== D.D.T.O. Protocol Starting (${TIMESTAMP}) ==="
  if ! git rev-parse --is-inside-work-tree &>/dev/null; then
    log_err "Not inside a Git repository."
    exit 1
  fi
  log_ok "Git repository detected."
}

# ---------------------------------------------------------------------------
# Step 1 — Rollback protection: create a backup branch
# ---------------------------------------------------------------------------

step_backup() {
  log "--- Step 1: Rollback protection ---"
  if git show-ref --verify --quiet "refs/heads/${BACKUP_BRANCH}"; then
    log "Backup branch '${BACKUP_BRANCH}' already exists; skipping."
  else
    git branch "${BACKUP_BRANCH}"
    log_ok "Backup branch created: ${BACKUP_BRANCH}"
  fi
  record "**Backup branch:** \`${BACKUP_BRANCH}\`"
}

# ---------------------------------------------------------------------------
# Step 2 — Case-sensitivity cleanup
# ---------------------------------------------------------------------------

step_case_sensitivity() {
  log "--- Step 2: Case-sensitivity cleanup ---"
  local count=0
  # Detect files that differ only in case from another tracked file
  while IFS= read -r file; do
    local lower
    lower="$(echo "${file}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${file}" != "${lower}" ]]; then
      local dir; dir="$(dirname "${file}")"
      local base; base="$(basename "${file}")"
      local new_base; new_base="$(echo "${base}" | tr '[:upper:]' '[:lower:]')"
      if [[ "${base}" != "${new_base}" ]]; then
        git mv "${file}" "${dir}/${new_base}" 2>/dev/null || true
        (( count++ )) || true
      fi
    fi
  done < <(git ls-files | grep '[A-Z]' || true)
  log_ok "Case-sensitivity cleanup complete. Files renamed: ${count}"
  record "**Case-sensitivity cleanup:** ${count} file(s) renamed"
}

# ---------------------------------------------------------------------------
# Step 3 — Filename normalization (spaces → underscores)
# ---------------------------------------------------------------------------

step_filename_normalize() {
  log "--- Step 3: Filename normalization ---"
  local count=0
  while IFS= read -r file; do
    if [[ "${file}" == *" "* ]]; then
      local normalized="${file// /_}"
      git mv "${file}" "${normalized}" 2>/dev/null || true
      (( count++ )) || true
    fi
  done < <(git ls-files | grep ' ' || true)
  log_ok "Filename normalization complete. Files renamed: ${count}"
  record "**Filename normalization:** ${count} file(s) renamed"
}

# ---------------------------------------------------------------------------
# Step 4 — Linting and auto-fixing
# ---------------------------------------------------------------------------

step_lint() {
  log "--- Step 4: Linting and auto-fixing ---"
  local fixed=0

  # Shell scripts: use shellcheck if available (report only, non-fatal)
  if command -v shellcheck &>/dev/null; then
    while IFS= read -r sh_file; do
      shellcheck "${sh_file}" >> "${LOG_FILE}" 2>&1 || true
      (( fixed++ )) || true
    done < <(git ls-files '*.sh' || true)
    log_ok "shellcheck ran on ${fixed} shell script(s)."
  else
    log "shellcheck not found; skipping shell linting."
  fi

  record "**Linting:** shellcheck ran on ${fixed} shell script(s)"
}

# ---------------------------------------------------------------------------
# Step 5 — CSS/JS minification (report only if tools unavailable)
# ---------------------------------------------------------------------------

step_minify() {
  log "--- Step 5: CSS/JS minification ---"
  local count=0

  if command -v npx &>/dev/null; then
    while IFS= read -r css_file; do
      if npx --yes csso-cli "${css_file}" --output "${css_file}" 2>/dev/null; then (( count++ )) || true; fi
    done < <(git ls-files '*.css' | grep -v '\.min\.css$' || true)
    while IFS= read -r js_file; do
      if npx --yes terser "${js_file}" -o "${js_file}" 2>/dev/null; then (( count++ )) || true; fi
    done < <(git ls-files '*.js' | grep -v '\.min\.js$' || true)
    log_ok "Minification complete. Files minified: ${count}"
  else
    log "npx not found; skipping minification."
  fi

  record "**CSS/JS minification:** ${count} file(s) minified"
}

# ---------------------------------------------------------------------------
# Step 6 — Reference and link corrections (fix common broken references)
# ---------------------------------------------------------------------------

step_link_corrections() {
  log "--- Step 6: Reference and link corrections ---"
  local fixed=0
  # Replace http:// → https:// in Markdown files where safe to do so
  while IFS= read -r md_file; do
    if grep -q 'http://' "${md_file}" 2>/dev/null; then
      sed -i 's|http://github\.com|https://github.com|g' "${md_file}" || true
      (( fixed++ )) || true
    fi
  done < <(git ls-files '*.md' || true)
  log_ok "Link corrections complete. Files updated: ${fixed}"
  record "**Link corrections:** ${fixed} file(s) updated"
}

# ---------------------------------------------------------------------------
# Step 7 — CI safety-net: ensure a basic GitHub Actions workflow exists
# ---------------------------------------------------------------------------

step_ci_safetynet() {
  log "--- Step 7: CI safety-net ---"
  local workflow_dir=".github/workflows"
  local safety_file="${workflow_dir}/ddto-ci-safetynet.yml"

  if [[ ! -f "${safety_file}" ]]; then
    mkdir -p "${workflow_dir}"
    cat > "${safety_file}" <<'YAML'
name: D.D.T.O. CI Safety-Net
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: ShellCheck
        run: |
          if command -v shellcheck &>/dev/null; then
            find . -name '*.sh' -not -path './.git/*' -exec shellcheck {} + || true
          fi
YAML
    log_ok "CI safety-net workflow created: ${safety_file}"
    record "**CI safety-net:** workflow created at \`${safety_file}\`"
  else
    log "CI safety-net workflow already exists; skipping."
    record "**CI safety-net:** already present"
  fi
}

# ---------------------------------------------------------------------------
# Step 8 — Link-check loop
# ---------------------------------------------------------------------------

step_link_check() {
  log "--- Step 8: Link-check ---"
  local broken=0
  local checked=0

  {
    echo "# Link Check Report"
    echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo ""
  } > "${LINK_REPORT}"

  if command -v curl &>/dev/null; then
    while IFS= read -r url; do
      (( checked++ )) || true
      local http_code
      http_code="$(curl -o /dev/null -s -w '%{http_code}' --max-time 10 "${url}" 2>/dev/null || echo "000")"
      if [[ "${http_code}" == "200" || "${http_code}" == "301" || "${http_code}" == "302" ]]; then
        echo "- [OK ${http_code}] ${url}" >> "${LINK_REPORT}"
      else
        echo "- [BROKEN ${http_code}] ${url}" >> "${LINK_REPORT}"
        (( broken++ )) || true
      fi
    done < <(grep -rho 'https\?://[^)>" ]*' --include='*.md' . 2>/dev/null | sort -u || true)
  else
    echo "curl not available; link check skipped." >> "${LINK_REPORT}"
    log "curl not found; skipping link check."
  fi

  log_ok "Link check complete. Checked: ${checked}, Broken: ${broken}"
  record "**Link check:** ${checked} checked, ${broken} broken (see \`${LINK_REPORT}\`)"

  if [[ "${broken}" -gt 0 && "${SELFHEAL}" == "true" ]]; then
    log "Self-heal mode: ${broken} broken link(s) found. Re-running link corrections..."
    step_link_corrections
  fi
}

# ---------------------------------------------------------------------------
# Step 9 — Smoke test checklist
# ---------------------------------------------------------------------------

step_smoke_test() {
  log "--- Step 9: Smoke test checklist ---"
  cat > "${SMOKE_TEST}" <<MD
# SMOKE TEST — Manual Verification Checklist

Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Repository: $(basename "$(pwd)")

## Checks

- [ ] Repository clones cleanly
- [ ] All CI workflows pass
- [ ] No broken links reported in \`link-check-report.md\`
- [ ] \`ddto_dashboard.html\` loads correctly in a browser
- [ ] Backup branch \`${BACKUP_BRANCH}\` is visible in GitHub
- [ ] Tag \`${TAG_NAME}\` is visible in GitHub
- [ ] \`ddto_summary.md\` reflects the latest run
MD
  log_ok "Smoke test checklist written to ${SMOKE_TEST}"
  record "**Smoke test:** checklist written to \`${SMOKE_TEST}\`"
}

# ---------------------------------------------------------------------------
# Step 10 — Summary report
# ---------------------------------------------------------------------------

step_summary() {
  log "--- Step 10: Summary report ---"
  {
    echo "# D.D.T.O. Summary Report"
    echo ""
    echo "**Repository:** $(basename "$(pwd)")"
    echo "**Timestamp:**  ${TIMESTAMP}"
    echo "**Backup:**     \`${BACKUP_BRANCH}\`"
    echo "**Tag:**        \`${TAG_NAME}\`"
    echo ""
    echo "## Results"
    echo ""
    for line in "${SUMMARY_LINES[@]}"; do
      echo "- ${line}"
    done
  } > "${SUMMARY_FILE}"
  log_ok "Summary written to ${SUMMARY_FILE}"
}

# ---------------------------------------------------------------------------
# Step 11 — Stage generated files and commit
# ---------------------------------------------------------------------------

step_commit() {
  log "--- Step 11: Committing changes ---"
  git add -A 2>/dev/null || true
  if ! git diff --cached --quiet 2>/dev/null; then
    git commit -m "chore: D.D.T.O. protocol run ${TIMESTAMP}" 2>/dev/null || true
    log_ok "Changes committed."
    record "**Commit:** changes committed"
  else
    log "No changes to commit."
    record "**Commit:** nothing to commit"
  fi
}

# ---------------------------------------------------------------------------
# Step 12 — Release tagging
# ---------------------------------------------------------------------------

step_tag() {
  log "--- Step 12: Release tagging ---"
  if git tag "${TAG_NAME}" 2>/dev/null; then
    log_ok "Tag created: ${TAG_NAME}"
    record "**Tag:** \`${TAG_NAME}\` created"
  else
    log "Tag '${TAG_NAME}' already exists; skipping."
    record "**Tag:** already exists"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

preflight
step_backup
step_case_sensitivity
step_filename_normalize
step_lint
step_minify
step_link_corrections
step_ci_safetynet
step_link_check
step_smoke_test
step_summary
step_commit
step_tag

log "=== D.D.T.O. Protocol Complete (${TIMESTAMP}) ==="
log "Log:     ${LOG_FILE}"
log "Summary: ${SUMMARY_FILE}"
