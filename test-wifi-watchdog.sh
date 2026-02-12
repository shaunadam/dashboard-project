#!/bin/bash
# Test script for WiFi watchdog recovery.
# Disconnects WiFi, triggers watchdog, and has a safety net to restore connectivity.
#
# Run with: sudo bash ./test-wifi-watchdog.sh
#
# Safe to run over SSH — uses systemd-run so the test survives SSH disconnects.
# View results with: journalctl -u wifi-test --no-pager

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Must run as root (sudo bash ./test-wifi-watchdog.sh)"
  exit 1
fi

# If not already running inside systemd-run, re-exec under systemd scope
if [ "${WIFI_TEST_IN_SYSTEMD:-}" != "1" ]; then
  echo "Launching test in systemd scope (survives SSH disconnect)..."
  echo "View results: journalctl -u wifi-test --no-pager"
  systemd-run --unit=wifi-test --description="WiFi Watchdog Test" \
    --setenv=WIFI_TEST_IN_SYSTEMD=1 \
    bash "$SCRIPT_DIR/test-wifi-watchdog.sh"
  echo "Test launched. Monitor with: journalctl -u wifi-test -f"
  exit 0
fi

# --- Running inside systemd scope from here ---

log() {
  echo "[wifi-test] $*"
}

log "=== WiFi Watchdog Test: $(date) ==="

# Record current state
log "--- Before disconnect ---"
nmcli device status 2>&1 || true

# Disconnect WiFi at device level
log ">>> Disconnecting wlan0..."
nmcli device disconnect wlan0 2>&1 || true

log ">>> WiFi down. Waiting 5 seconds before triggering watchdog..."
sleep 5

# Verify it's actually down
log "--- After disconnect ---"
nmcli device status 2>&1 || true

# Trigger the watchdog directly (not via systemctl, since we ARE in systemd)
log ">>> Triggering wifi-watchdog.sh directly..."
bash "$SCRIPT_DIR/watchdog/wifi-watchdog.sh" 2>&1 || true

# Wait for network to settle
sleep 10

# Check result
log "--- After watchdog ---"
nmcli device status 2>&1 || true

if nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep -q "^wlan0:connected$"; then
  log "RESULT: Watchdog recovered WiFi successfully!"
else
  log "RESULT: Watchdog FAILED to recover. Applying safety net..."
  nmcli device connect wlan0 2>&1 || true
  sleep 10
  nmcli device status 2>&1 || true

  if nmcli -t -f DEVICE,STATE device status 2>/dev/null | grep -q "^wlan0:connected$"; then
    log "Safety net restored connectivity."
  else
    log "Safety net ALSO failed. Manual intervention required."
  fi
fi

log "=== Test complete ==="
