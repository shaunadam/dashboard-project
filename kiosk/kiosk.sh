#!/bin/bash
set -euo pipefail

# Kiosk launcher — starts Chromium in fullscreen kiosk mode.
# All configurable values are loaded from config.json via lib/config.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/lib/config.sh"

# Load configuration
DASHBOARD_URL="$(cfg_require '.dashboard.url')"
LOAD_WAIT="$(cfg_get '.kiosk.desktop_load_wait_seconds')"
LOAD_WAIT="${LOAD_WAIT:-10}"
USER_DATA_DIR="$(cfg_require '.kiosk.user_data_dir')"
ONBOARD_SIZE="$(cfg_get '.kiosk.onboard_size')"
ONBOARD_SIZE="${ONBOARD_SIZE:-800x300}"

# Set display environment variable
export DISPLAY=:0

# Wait for desktop to load
sleep "$LOAD_WAIT"

# Hide mouse cursor
unclutter -idle 0.1 &

# Start on-screen keyboard (auto-shows on text field focus)
GDK_BACKEND=x11 onboard --size="$ONBOARD_SIZE" &

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Start chromium in kiosk mode
chromium-browser \
  --kiosk \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-restore-session-state \
  --disable-features=TranslateUI \
  --no-first-run \
  --fast \
  --fast-start \
  --disable-default-apps \
  --password-store=basic \
  --display=:0 \
  --user-data-dir="$USER_DATA_DIR" \
  "$DASHBOARD_URL"
