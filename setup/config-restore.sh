#!/usr/bin/env bash
# Restore secrets.json from a backup made by config-backup.sh. Also accepts an
# old single-file config.json, from which only the credential keys are taken.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets.json"

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
required_keys=(".mqtt.username" ".mqtt.password" ".wifi.ssid" ".wifi.password")
for key in "${required_keys[@]}"; do
  if [[ "$(jq -r "${key} // empty" "${BACKUP}")" == "" ]]; then
    log "ERROR: Backup missing required key: ${key}"
    exit 1
  fi
done

# Copy across only the credential keys. A backup of an old single-file
# config.json would otherwise shadow values that now live in config.json.
jq '{
  mqtt: {
    username: .mqtt.username,
    password: .mqtt.password
  },
  wifi: {
    ssid: .wifi.ssid,
    password: .wifi.password
  }
}' "${BACKUP}" > "${SECRETS_FILE}"

chmod 600 "${SECRETS_FILE}"
log "Secrets restored from: ${BACKUP}"

# Restart services if systemd is available
if command -v systemctl >/dev/null 2>&1; then
  log "Restarting services..."
  # mqtt-listener is a systemd *user* service (see setup/systemd-units.sh).
  systemctl --user restart mqtt-listener.service 2>/dev/null && log "mqtt-listener restarted" || log "WARNING: mqtt-listener restart failed (may not be installed yet)"
  log "Services restarted. Run verify.sh to confirm."
else
  log "systemctl not available — skipping service restart."
fi
