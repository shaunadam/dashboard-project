#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() { echo "[switch-branch] $*"; }

if [[ $# -lt 1 ]]; then
  log "Usage: $0 <branch-name>"
  log ""
  log "Switches git branch and restarts all dashboard services."
  log "Config is git-ignored, so it persists across switches."
  log ""
  log "Examples:"
  log "  $0 main              # Switch to production"
  log "  $0 phase-1-dev       # Switch to development"
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

# Verify branch exists
if ! git rev-parse --verify "${TARGET_BRANCH}" >/dev/null 2>&1; then
  log "ERROR: Branch '${TARGET_BRANCH}' does not exist."
  log "Available branches:"
  git branch --list
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
log "Switching from '${CURRENT_BRANCH}' to '${TARGET_BRANCH}'..."

# Switch branch
git checkout "${TARGET_BRANCH}"
log "Now on branch: $(git branch --show-current)"

# Check if config.json exists (git-ignored, should persist)
if [[ ! -f "${REPO_ROOT}/config.json" ]]; then
  log "WARNING: config.json not found after branch switch."
  log "This branch may need bootstrap.sh to generate config."
  log "Run: ./setup/bootstrap.sh"
fi

# Restart services
if command -v systemctl >/dev/null 2>&1; then
  log "Restarting services..."

  # Regenerate systemd files (paths may differ between branches)
  log "Regenerating systemd service files..."

  # Touchscreen check service
  if [[ -f "${REPO_ROOT}/touchscreen/touchscreen-check.sh" ]]; then
    sudo tee /etc/systemd/system/touchscreen-check.service > /dev/null << SVCEOF
[Unit]
Description=Touchscreen Detection and Auto-Reboot Service
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=${REPO_ROOT}/touchscreen/touchscreen-check.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVCEOF
  fi

  # MQTT listener service
  if [[ -f "${REPO_ROOT}/mqtt/mqtt_listener.py" ]]; then
    sudo tee /etc/systemd/system/mqtt-listener.service > /dev/null << SVCEOF
[Unit]
Description=MQTT Display Control Listener
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${REPO_ROOT}/mqtt/mqtt_listener.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
User=${USER}
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
SVCEOF
  fi

  sudo systemctl daemon-reload
  sudo systemctl restart mqtt-listener.service 2>/dev/null && log "mqtt-listener restarted" || log "WARNING: mqtt-listener restart failed"
  log "Services updated."
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
