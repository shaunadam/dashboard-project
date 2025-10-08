#!/usr/bin/env bash
set -euo pipefail

# Skip if you drop an empty file on the boot partition to recover from kiosk lockouts
if [[ -f /boot/disable-usb-cycle ]]; then
  echo "[usb_reset] Skipping due to /boot/disable-usb-cycle"
  exit 0
fi

# Defaults (can be overridden by env vars from the service)
HUB="${HUB:-1-1}"
PORT="${PORT:-1}"
SLEEP_BEFORE="${SLEEP_BEFORE:-10}"

sleep "$SLEEP_BEFORE"

echo "[usb_reset] Cycling hub $HUB port $PORT…"
uhubctl -l "$HUB" -p "$PORT" -a off || true
sleep 2
uhubctl -l "$HUB" -p "$PORT" -a on  || true

# Nudge input so events appear promptly
udevadm trigger --subsystem-match=usb --action=add   || true
udevadm trigger --subsystem-match=input --action=add || true
udevadm settle || true

echo "[usb_reset] Done."
