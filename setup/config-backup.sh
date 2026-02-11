#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.json"

log() { echo "[config-backup] $*"; }

if [[ ! -f "${CONFIG_FILE}" ]]; then
  log "ERROR: No config.json found at ${CONFIG_FILE}"
  log "Run bootstrap.sh first to create configuration."
  exit 1
fi

# Accept destination as argument or default to home directory
DEST="${1:-${HOME}/dashboard-config-backup.json}"

cp "${CONFIG_FILE}" "${DEST}"
chmod 600 "${DEST}"
log "Configuration backed up to: ${DEST}"
log "Store this file safely — it contains MQTT credentials."
