#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() { echo "[switch-branch] $*"; }

if [[ $# -lt 1 ]]; then
  log "Usage: $0 <branch-name>"
  log ""
  log "Fetches from origin, switches branch, and restarts dashboard services."
  log "secrets.json is git-ignored, so credentials persist across switches;"
  log "config.json is tracked, so settings come along with the branch."
  log ""
  log "Examples:"
  log "  $0 main              # Switch to production"
  log "  $0 feat/my-feature   # Switch to a feature branch"
  exit 1
fi

TARGET_BRANCH="$1"

cd "${REPO_ROOT}"

# Check for uncommitted changes
if ! git diff --quiet || ! git diff --staged --quiet; then
  log "ERROR: Uncommitted changes detected. Commit or stash first."
  git status --short
  exit 1
fi

log "Fetching from origin..."
git fetch origin

# Prefer the up-to-date remote branch; fall back to a Pi-local-only branch.
if git rev-parse --verify "origin/${TARGET_BRANCH}" >/dev/null 2>&1; then
  CHECKOUT_REF="origin/${TARGET_BRANCH}"
elif git rev-parse --verify "${TARGET_BRANCH}" >/dev/null 2>&1; then
  CHECKOUT_REF="${TARGET_BRANCH}"
else
  log "ERROR: Branch '${TARGET_BRANCH}' does not exist locally or on origin."
  log "Available branches:"
  git branch -a --list
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
log "Switching from '${CURRENT_BRANCH}' to '${TARGET_BRANCH}' (${CHECKOUT_REF})..."
git checkout -B "${TARGET_BRANCH}" "${CHECKOUT_REF}"
log "Now on branch: $(git branch --show-current)"

# Check if secrets.json exists (git-ignored, should persist). config.json is
# tracked, so the branch switch brings it along.
if [[ ! -f "${REPO_ROOT}/secrets.json" ]]; then
  log "WARNING: secrets.json not found after branch switch."
  log "Run: ./setup/bootstrap.sh   (or ./setup/migrate-secrets.sh <old-config.json>)"
fi

# Restart services
if command -v systemctl >/dev/null 2>&1; then
  if [[ -f "${SCRIPT_DIR}/systemd-units.sh" ]]; then
    log "Regenerating systemd service files (paths may differ between branches)..."
    # shellcheck source=./systemd-units.sh
    source "${SCRIPT_DIR}/systemd-units.sh"
    install_systemd_units

    log "Restarting long-running services to pick up new code..."
    # mqtt-listener is a systemd *user* service (needs the graphical session
    # for wlopm); browser-watchdog is a system service running as $USER.
    # touchscreen-check/wifi-ensure only run at boot and wifi-watchdog is
    # timer-triggered, so none of those need restarting here.
    systemctl --user restart mqtt-listener.service 2>/dev/null && log "mqtt-listener restarted" || log "WARNING: mqtt-listener restart failed"
    sudo systemctl restart browser-watchdog.service 2>/dev/null && log "browser-watchdog restarted" || log "WARNING: browser-watchdog restart failed"
    log "Services updated."
  else
    log "setup/systemd-units.sh not found on this branch — skipping service regeneration."
  fi
else
  log "systemctl not available — skipping service restart."
fi

# Run verification if available
if [[ -f "${REPO_ROOT}/setup/verify.sh" ]]; then
  log "Running verification..."
  bash "${REPO_ROOT}/setup/verify.sh" && log "Verification passed!" || log "WARNING: Verification found issues (see above)"
else
  log "verify.sh not found on this branch — skipping verification."
fi

log "Branch switch complete."
