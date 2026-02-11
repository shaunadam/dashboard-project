#!/usr/bin/env bash
# Shared configuration loader for bash scripts.
# Source this file to access config.json via cfg_get / cfg_require.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/config.sh"
#   url="$(cfg_get '.dashboard.url')"
#   broker="$(cfg_require '.mqtt.broker')"

set -euo pipefail

# Derive REPO_ROOT from this file's location (lib/ is one level below root).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.json"

# Verify jq is available.
if ! command -v jq >/dev/null 2>&1; then
  echo "[config] ERROR: jq is required but not installed." >&2
  echo "[config] Install it with: sudo apt-get install -y jq" >&2
  exit 1
fi

# Verify config file exists.
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "[config] ERROR: Configuration file not found: ${CONFIG_FILE}" >&2
  echo "[config] Run setup/bootstrap.sh to generate config.json from the template." >&2
  exit 1
fi

# cfg_get <jq_path>
# Extract a value from config.json. Returns empty string if path not found.
cfg_get() {
  local path="$1"
  local value
  value="$(jq -r "${path} // empty" "${CONFIG_FILE}" 2>/dev/null)" || true
  echo "${value}"
}

# cfg_require <jq_path>
# Extract a value from config.json, exiting with an error if missing or null.
cfg_require() {
  local path="$1"
  local value
  value="$(cfg_get "${path}")"
  if [ -z "${value}" ]; then
    echo "[config] ERROR: Required config value missing: ${path}" >&2
    echo "[config] Check ${CONFIG_FILE} and ensure the value is set." >&2
    exit 1
  fi
  echo "${value}"
}
