#!/usr/bin/env bash
# Extract the credential keys out of an old single-file config.json (or any
# backup of one) into secrets.json, so nobody has to retype a password when
# upgrading to the split config.json / secrets.json layout.
#
# Usage:
#   ./setup/migrate-secrets.sh                  # reads ./config.json.legacy
#   ./setup/migrate-secrets.sh /path/to/old.json
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets.json"

log() { echo "[migrate-secrets] $*"; }

SOURCE="${1:-${REPO_ROOT}/config.json.legacy}"

if [[ ! -f "${SOURCE}" ]]; then
  log "ERROR: Source file not found: ${SOURCE}"
  log "Pass the path to your old config.json (or a backup of it)."
  exit 1
fi

if ! jq empty "${SOURCE}" 2>/dev/null; then
  log "ERROR: ${SOURCE} is not valid JSON"
  exit 1
fi

if [[ -f "${SECRETS_FILE}" ]]; then
  log "ERROR: ${SECRETS_FILE} already exists — refusing to overwrite."
  log "Delete it first if you really want to regenerate it."
  exit 1
fi

# Pull only the four credential keys across; everything else in the old file
# is now tracked in config.json and would only shadow it.
jq '{
  mqtt: {
    username: .mqtt.username,
    password: .mqtt.password
  },
  wifi: {
    ssid: .wifi.ssid,
    password: .wifi.password
  }
}' "${SOURCE}" > "${SECRETS_FILE}"

chmod 600 "${SECRETS_FILE}"

# Fail loudly rather than leaving a half-populated secrets file behind.
missing=()
for key in .mqtt.username .mqtt.password .wifi.ssid .wifi.password; do
  if [[ "$(jq -r "${key} // empty" "${SECRETS_FILE}")" == "" ]]; then
    missing+=("${key}")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  rm -f "${SECRETS_FILE}"
  log "ERROR: ${SOURCE} had no value for: ${missing[*]}"
  log "Nothing written. Run setup/bootstrap.sh to enter them by hand."
  exit 1
fi

log "Credentials migrated to ${SECRETS_FILE} (mode 600)."
log "You can now delete ${SOURCE} — the rest of it lives in config.json."
