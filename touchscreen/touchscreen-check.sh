#!/bin/bash
set -euo pipefail

# Touchscreen Detection and Auto-Reboot Script
# Checks for touchscreen after boot and performs ONE automatic reboot
# if not detected, to trigger warm-boot USB enumeration.
# All configurable values are loaded from config.json via lib/config.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/lib/config.sh"

# Load configuration
TOUCHSCREEN_ID="$(cfg_require '.touchscreen.usb_device_id')"
FLAG_FILE="$(cfg_get '.system.reboot_flag_file')"
FLAG_FILE="${FLAG_FILE:-/var/lib/dashboard-project/touchscreen-reboot-attempted}"
LOG_TAG="$(cfg_get '.system.log_tag_touchscreen')"
LOG_TAG="${LOG_TAG:-touchscreen-check}"
WAIT_TIME="$(cfg_get '.touchscreen.detection_wait_seconds')"
WAIT_TIME="${WAIT_TIME:-60}"

log_message() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

# Wait for system to fully stabilize
log_message "Waiting ${WAIT_TIME} seconds for system and hardware initialization..."
sleep "$WAIT_TIME"

# Check if touchscreen is present
if lsusb | grep -q "$TOUCHSCREEN_ID"; then
  log_message "SUCCESS: Touchscreen detected (${TOUCHSCREEN_ID})"

  # Clear flag file if it exists (clean slate for next cold boot)
  if [ -f "$FLAG_FILE" ]; then
    rm -f "$FLAG_FILE"
    log_message "Cleared reboot flag file"
  fi

  exit 0
fi

# Touchscreen not detected
log_message "WARNING: Touchscreen not detected (${TOUCHSCREEN_ID})"

# Check if we've already attempted a reboot
if [ -f "$FLAG_FILE" ]; then
  log_message "ERROR: Reboot already attempted but touchscreen still missing"
  log_message "Manual intervention required - check USB connections and monitor power"
  exit 1
fi

# Create flag file and reboot
log_message "Creating reboot flag and initiating system reboot..."
mkdir -p "$(dirname "$FLAG_FILE")"
touch "$FLAG_FILE"

log_message "REBOOTING: Touchscreen not detected, attempting warm boot recovery..."
systemctl reboot
