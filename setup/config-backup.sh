#!/usr/bin/env bash
# Back up secrets.json. Non-secret configuration lives in the tracked
# config.json, which git already backs up — this only covers what git can't.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets.json"

log() { echo "[config-backup] $*"; }

if [[ ! -f "${SECRETS_FILE}" ]]; then
  log "ERROR: No secrets.json found at ${SECRETS_FILE}"
  log "Run bootstrap.sh first to create it."
  exit 1
fi

# Accept destination as argument or default to home directory
DEST="${1:-${HOME}/dashboard-secrets-backup.json}"

cp "${SECRETS_FILE}" "${DEST}"
chmod 600 "${DEST}"
log "Secrets backed up to: ${DEST}"
log "Store this file safely — it contains MQTT and WiFi credentials."
