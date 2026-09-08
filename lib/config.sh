#!/usr/bin/env bash
# Shared configuration loader for bash scripts.
# Source this file to access configuration via cfg_get / cfg_require.
#
# Configuration is split across two files, both at the repo root:
#   config.json   - tracked in git. Everything that is not a secret.
#   secrets.json  - git-ignored, chmod 600. Credentials only.
# They are deep-merged at source time (secrets win), so callers just ask for
# a jq path and never care which file a value came from.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/config.sh"
#   url="$(cfg_get '.dashboard.url')"
#   password="$(cfg_require '.mqtt.password')"

set -euo pipefail

# Derive REPO_ROOT from this file's location (lib/ is one level below root).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/config.json"
SECRETS_FILE="${REPO_ROOT}/secrets.json"

# Verify jq is available.
if ! command -v jq >/dev/null 2>&1; then
  echo "[config] ERROR: jq is required but not installed." >&2
  echo "[config] Install it with: sudo apt-get install -y jq" >&2
  exit 1
fi

# Verify both files exist. config.json ships with the repo, so a missing one
# means a broken checkout; secrets.json is per-device and must be generated.
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "[config] ERROR: Configuration file not found: ${CONFIG_FILE}" >&2
  echo "[config] config.json is tracked in git — check out the repo again." >&2
  exit 1
fi

if [ ! -f "${SECRETS_FILE}" ]; then
  echo "[config] ERROR: Secrets file not found: ${SECRETS_FILE}" >&2
  echo "[config] Create it with setup/bootstrap.sh, setup/migrate-secrets.sh," >&2
  echo "[config] or setup/config-restore.sh <backup.json>." >&2
  exit 1
fi

# Merge once, here, rather than on every lookup. jq's `*` operator merges
# objects recursively, so secrets.json only carries the keys it overrides.
if ! CONFIG_JSON="$(jq -s '.[0] * .[1]' "${CONFIG_FILE}" "${SECRETS_FILE}" 2>&1)"; then
  echo "[config] ERROR: Could not merge ${CONFIG_FILE} and ${SECRETS_FILE}." >&2
  echo "[config] jq said: ${CONFIG_JSON}" >&2
  exit 1
fi

# cfg_get <jq_path>
# Extract a value from the merged config. Returns empty string if not found.
cfg_get() {
  local path="$1"
  local value
  value="$(jq -r "${path} // empty" <<< "${CONFIG_JSON}" 2>/dev/null)" || true
  echo "${value}"
}

# cfg_require <jq_path>
# Extract a value from the merged config, exiting if missing or null.
cfg_require() {
  local path="$1"
  local value
  value="$(cfg_get "${path}")"
  if [ -z "${value}" ]; then
    echo "[config] ERROR: Required config value missing: ${path}" >&2
    echo "[config] Check ${CONFIG_FILE} and ${SECRETS_FILE}." >&2
    exit 1
  fi
  echo "${value}"
}
