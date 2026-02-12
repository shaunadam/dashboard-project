#!/bin/bash
set -euo pipefail

# Kiosk launcher — starts Chromium in fullscreen kiosk mode.
# Includes touch-friendly flags, crash state cleanup, and restart loop.
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
LOG_TAG="$(cfg_get '.system.log_tag_kiosk')"
LOG_TAG="${LOG_TAG:-kiosk}"

log_message() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

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

log_message "Kiosk launcher started, entering restart loop"

# Restart loop: if Chromium exits (crash or otherwise), clean up and relaunch
while true; do
  # Clean up Chromium crash state to prevent "restore pages?" dialog
  CHROMIUM_PREFS="${USER_DATA_DIR}/Default/Preferences"
  if [ -f "$CHROMIUM_PREFS" ]; then
    sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "$CHROMIUM_PREFS"
    sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' "$CHROMIUM_PREFS"
    log_message "Cleaned Chromium crash state in Preferences"
  fi

  # Start Chromium in kiosk mode with touch-friendly flags
  # --remote-debugging-port enables CDP (Chrome DevTools Protocol) so
  # browser-watchdog.sh can navigate back to the dashboard URL after idle
  # timeout, rather than just refreshing the current page.
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
    --disable-touch-drag-drop \
    --overscroll-history-navigation=0 \
    --disable-pinch \
    --remote-debugging-port=9222 \
    "$DASHBOARD_URL"

  # If Chromium exits (crash or otherwise), log and restart
  log_message "Chromium exited, restarting in 5 seconds..."
  sleep 5
done
