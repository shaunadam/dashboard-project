#!/bin/bash
set -euo pipefail

# USB Touchscreen Diagnostic Script
# Usage: ./diagnose-usb.sh [cold|warm]

if [ $# -ne 1 ] || { [ "$1" != "cold" ] && [ "$1" != "warm" ]; }; then
  echo "Usage: $0 [cold|warm]"
  echo "  cold - Run after a cold boot (power cycle)"
  echo "  warm - Run after a warm reboot (sudo reboot)"
  exit 1
fi

BOOT_TYPE="$1"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="$HOME/dashboard-project/diagnostics"
OUTPUT_FILE="${OUTPUT_DIR}/usb-diag-${BOOT_TYPE}-${TIMESTAMP}.txt"

# Create diagnostics directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

echo "Capturing USB diagnostics for ${BOOT_TYPE} boot..."
echo "Output file: ${OUTPUT_FILE}"

{
  echo "========================================="
  echo "USB Touchscreen Diagnostic Report"
  echo "Boot Type: ${BOOT_TYPE}"
  echo "Timestamp: ${TIMESTAMP}"
  echo "========================================="
  echo ""

  echo "--- System Info ---"
  uname -a
  echo ""

  echo "--- Uptime ---"
  uptime
  echo ""

  echo "--- USB Devices (lsusb) ---"
  lsusb
  echo ""

  echo "--- USB Devices (verbose for ILITEK 222a:0001) ---"
  lsusb -v -d 222a:0001 2>&1 || echo "ILITEK device not found"
  echo ""

  echo "--- All USB Device Details ---"
  lsusb -v 2>&1
  echo ""

  echo "--- Input Devices (/dev/input/) ---"
  ls -la /dev/input/
  echo ""

  echo "--- Input Device Event Handlers ---"
  cat /proc/bus/input/devices
  echo ""

  echo "--- dmesg: USB subsystem (last 200 lines) ---"
  dmesg | grep -i usb | tail -n 200
  echo ""

  echo "--- dmesg: Touchscreen/Input/HID (last 200 lines) ---"
  dmesg | grep -iE "touch|input|hid" | tail -n 200
  echo ""

  echo "--- dmesg: ILITEK device ---"
  dmesg | grep -i ilitek
  echo ""

  echo "--- dmesg: Full kernel log (last 500 lines) ---"
  dmesg | tail -n 500
  echo ""

  echo "--- Loaded Kernel Modules (USB/HID/Input related) ---"
  lsmod | grep -iE "usb|hid|input|touch"
  echo ""

  echo "========================================="
  echo "Diagnostic capture complete"
  echo "========================================="
} > "$OUTPUT_FILE"

echo "Done! Diagnostic data saved to:"
echo "  ${OUTPUT_FILE}"
echo ""
echo "Next steps:"
if [ "$BOOT_TYPE" = "cold" ]; then
  echo "  1. Verify touchscreen is NOT working"
  echo "  2. After capturing, run 'sudo reboot'"
  echo "  3. After warm reboot, run: ./diagnose-usb.sh warm"
else
  echo "  1. Verify touchscreen IS working"
  echo "  2. Compare the cold vs warm diagnostic files"
fi
