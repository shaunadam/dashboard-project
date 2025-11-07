#!/bin/bash
set -euo pipefail

# USB Touchscreen Re-scan Script
# Forces re-enumeration of USB devices to detect slow-to-initialize touchscreen

LOG_TAG="usb-rescan"

log_message() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

# Wait for system to stabilize
log_message "Waiting 5 seconds for system initialization..."
sleep 5

# Verify the USB hub device exists (VIA Labs 2109:3431)
if ! lsusb | grep -q "2109:3431"; then
  log_message "ERROR: VIA Labs USB hub not found"
  exit 1
fi

log_message "Found USB hub: VIA Labs 2109:3431"

# The hub is at USB path 1-1 (Bus 1, Port 1)
HUB_PATH="/sys/bus/usb/devices/1-1"

if [ ! -d "$HUB_PATH" ]; then
  log_message "ERROR: Hub path not found: $HUB_PATH"
  exit 1
fi

log_message "Hub path: $HUB_PATH"

# Check if touchscreen is already detected
if lsusb | grep -q "222a:0001"; then
  log_message "Touchscreen already detected, no rescan needed"
  exit 0
fi

log_message "Touchscreen not detected, forcing USB bus rescan..."

# Method 1: Unbind and rebind the hub driver
if [ -f "$HUB_PATH/authorized" ]; then
  echo 0 > "$HUB_PATH/authorized"
  sleep 1
  echo 1 > "$HUB_PATH/authorized"
  log_message "Hub authorized toggled"
fi

# Wait for re-enumeration
sleep 3

# Check if touchscreen appeared
if lsusb | grep -q "222a:0001"; then
  log_message "SUCCESS: Touchscreen detected after rescan!"
  exit 0
else
  log_message "WARNING: Touchscreen still not detected after rescan"
  exit 1
fi
