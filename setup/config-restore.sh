#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.json"

log() { echo "[config-restore] $*"; }

if [[ $# -lt 1 ]]; then
  log "Usage: $0 /path/to/backup.json"
  exit 1
fi

BACKUP="$1"

if [[ ! -f "${BACKUP}" ]]; then
  log "ERROR: Backup file not found: ${BACKUP}"
  exit 1
fi

# Validate the backup is valid JSON
if ! jq empty "${BACKUP}" 2>/dev/null; then
  log "ERROR: Backup file is not valid JSON"
  exit 1
fi

# Validate required keys
required_keys=(".dashboard.url" ".mqtt.broker" ".mqtt.port" ".touchscreen.usb_device_id")
for key in "${required_keys[@]}"; do
  if [[ "$(jq -r "${key} // empty" "${BACKUP}")" == "" ]]; then
    log "ERROR: Backup missing required key: ${key}"
    exit 1
  fi
done

# Restore
cp "${BACKUP}" "${CONFIG_FILE}"
chmod 600 "${CONFIG_FILE}"
log "Configuration restored from: ${BACKUP}"

# Restart services if systemd is available
if command -v systemctl >/dev/null 2>&1; then
  log "Restarting services..."
  # mqtt-listener is a systemd *user* service (see setup/systemd-units.sh).
  systemctl --user restart mqtt-listener.service 2>/dev/null && log "mqtt-listener restarted" || log "WARNING: mqtt-listener restart failed (may not be installed yet)"
  log "Services restarted. Run verify.sh to confirm."
else
  log "systemctl not available — skipping service restart."
fi
