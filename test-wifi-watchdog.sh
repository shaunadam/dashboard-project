#!/bin/bash
# Test script for WiFi watchdog recovery.
# Disconnects WiFi, triggers watchdog, and has a safety net to restore connectivity.
# Run with: sudo bash ./test-wifi-watchdog.sh
#
# Safe to run over SSH — includes automatic recovery if watchdog fails.

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: Must run as root (sudo bash ./test-wifi-watchdog.sh)"
  exit 1
fi

LOG="/tmp/wifi-watchdog-test.log"
echo "=== WiFi Watchdog Test: $(date) ===" | tee "$LOG"

# Record current state
echo "" | tee -a "$LOG"
echo "--- Before disconnect ---" | tee -a "$LOG"
nmcli device status 2>&1 | tee -a "$LOG" || true

# Disconnect WiFi at device level
echo "" | tee -a "$LOG"
echo ">>> Disconnecting wlan0..." | tee -a "$LOG"
nmcli device disconnect wlan0 2>&1 | tee -a "$LOG" || true

echo ">>> WiFi down. Waiting 5 seconds before triggering watchdog..." | tee -a "$LOG"
sleep 5

# Verify it's actually down
echo "" | tee -a "$LOG"
echo "--- After disconnect ---" | tee -a "$LOG"
nmcli device status 2>&1 | tee -a "$LOG" || true

# Trigger the watchdog manually (don't wait for timer)
echo "" | tee -a "$LOG"
echo ">>> Triggering wifi-watchdog.service now..." | tee -a "$LOG"
# Run synchronously — systemctl start blocks until the oneshot service finishes
systemctl start wifi-watchdog.service 2>&1 | tee -a "$LOG" || true

# Wait a bit more for network to settle
sleep 10

# Capture watchdog journal output
echo "" | tee -a "$LOG"
echo "--- Watchdog journal ---" | tee -a "$LOG"
journalctl -u wifi-watchdog --no-pager --since "5 minutes ago" 2>&1 | tee -a "$LOG" || true

# Check result
echo "" | tee -a "$LOG"
echo "--- After watchdog ---" | tee -a "$LOG"
nmcli device status 2>&1 | tee -a "$LOG" || true

if nmcli device status 2>/dev/null | grep -q "wlan0.*connected"; then
  echo "" | tee -a "$LOG"
  echo "RESULT: Watchdog recovered WiFi successfully!" | tee -a "$LOG"
else
  echo "" | tee -a "$LOG"
  echo "RESULT: Watchdog FAILED to recover. Applying safety net..." | tee -a "$LOG"
  nmcli device connect wlan0 2>&1 | tee -a "$LOG" || true
  sleep 10
  nmcli device status 2>&1 | tee -a "$LOG" || true
  echo "Safety net applied. Check $LOG for details." | tee -a "$LOG"
fi

echo "" | tee -a "$LOG"
echo "=== Test complete. Full log at $LOG ===" | tee -a "$LOG"
