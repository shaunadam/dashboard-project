#!/bin/bash
set -euo pipefail

# Browser Watchdog - Returns to home page after inactivity timeout.
# Monitors X11 idle time via xprintidle and reloads browser after timeout.
# Also detects WiFi recovery signal to reload dashboard after network restoration.
# All configurable values are loaded from config.json via lib/config.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/lib/config.sh"

# Load configuration (required values)
DASHBOARD_URL="$(cfg_require '.dashboard.url')"

# Load configuration (optional values with sensible defaults)
INACTIVITY_TIMEOUT="$(cfg_get '.browser.inactivity_timeout_seconds')"
INACTIVITY_TIMEOUT="${INACTIVITY_TIMEOUT:-600}"
LOG_TAG="$(cfg_get '.system.log_tag_browser')"
LOG_TAG="${LOG_TAG:-browser-watchdog}"

# Convert timeout to milliseconds for xprintidle comparison
IDLE_TIMEOUT_MS=$((INACTIVITY_TIMEOUT * 1000))

# WiFi recovery signal file (touched by wifi-watchdog.sh after successful recovery)
WIFI_RECOVERY_SIGNAL="/tmp/wifi-recovered"

log_message() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

log_message "Browser watchdog started (idle timeout: ${INACTIVITY_TIMEOUT}s / ${IDLE_TIMEOUT_MS}ms)"

while true; do
  # Check WiFi recovery signal
  if [ -f "$WIFI_RECOVERY_SIGNAL" ]; then
    log_message "WiFi recovery detected, reloading dashboard"
    rm -f "$WIFI_RECOVERY_SIGNAL"
    DISPLAY=:0 xdotool key F5
    sleep 10  # Brief pause after reload
    continue
  fi

  # Check idle time
  IDLE_MS=$(DISPLAY=:0 xprintidle 2>/dev/null || echo "0")
  if [ "$IDLE_MS" -gt "$IDLE_TIMEOUT_MS" ]; then
    log_message "Idle timeout reached (${IDLE_MS}ms > ${IDLE_TIMEOUT_MS}ms), reloading dashboard"
    DISPLAY=:0 xdotool key F5
    # Wait full timeout before checking again to avoid rapid-fire reloads
    sleep "$INACTIVITY_TIMEOUT"
  fi

  sleep 10  # Check every 10 seconds
done
