#!/bin/bash
set -euo pipefail

# Browser Watchdog - Returns to home dashboard after being away too long.
# Polls the current browser URL via CDP HTTP endpoint and kills Chromium
# if the user has been on a non-dashboard page longer than the timeout.
# The kiosk.sh restart loop relaunches Chromium at the dashboard URL.
# Also detects WiFi recovery signal to trigger a restart after network restoration.
# All configurable values are loaded from config.json via lib/config.sh.
#
# Requires Chromium to be launched with --remote-debugging-port=9222 (see kiosk.sh).

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

# WiFi recovery signal file (touched by wifi-watchdog.sh after successful recovery)
WIFI_RECOVERY_SIGNAL="/tmp/wifi-recovered"

# Track when we first noticed the browser was away from the dashboard
AWAY_SINCE=0

log_message() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

# get_current_url - Get the current browser URL via CDP HTTP endpoint.
# Returns empty string if Chromium isn't ready.
get_current_url() {
  curl -s --max-time 5 "http://localhost:9222/json" 2>/dev/null \
    | python3 -c "import sys,json; tabs=json.load(sys.stdin); print(tabs[0]['url'] if tabs else '')" 2>/dev/null \
    || echo ""
}

# restart_browser - Kill Chromium so the kiosk.sh restart loop relaunches
# it at the configured dashboard URL.
restart_browser() {
  log_message "Restarting browser to return to dashboard"
  pkill chromium 2>/dev/null || true
}

log_message "Browser watchdog started (away timeout: ${INACTIVITY_TIMEOUT}s)"

while true; do
  # Check WiFi recovery signal
  if [ -f "$WIFI_RECOVERY_SIGNAL" ]; then
    log_message "WiFi recovery detected, restarting browser"
    rm -f "$WIFI_RECOVERY_SIGNAL" 2>/dev/null || true
    restart_browser
    AWAY_SINCE=0
    sleep 15  # Wait for Chromium to relaunch
    continue
  fi

  # Get the current browser URL
  CURRENT_URL="$(get_current_url)"

  if [ -z "$CURRENT_URL" ]; then
    # Chromium not ready yet, wait
    sleep 10
    continue
  fi

  NOW="$(date +%s)"

  # Check if we're on the dashboard
  if [ "$CURRENT_URL" = "$DASHBOARD_URL" ] || [ "$CURRENT_URL" = "${DASHBOARD_URL}/" ]; then
    # On dashboard — reset timer
    if [ "$AWAY_SINCE" -ne 0 ]; then
      log_message "Back on dashboard"
    fi
    AWAY_SINCE=0
  elif [ "$AWAY_SINCE" -eq 0 ]; then
    # Just navigated away — start the timer
    AWAY_SINCE="$NOW"
    log_message "Navigated away from dashboard to: $CURRENT_URL"
  else
    # Still away — check if timeout exceeded
    AWAY_DURATION=$((NOW - AWAY_SINCE))
    if [ "$AWAY_DURATION" -ge "$INACTIVITY_TIMEOUT" ]; then
      log_message "Away from dashboard for ${AWAY_DURATION}s (timeout: ${INACTIVITY_TIMEOUT}s), returning"
      restart_browser
      AWAY_SINCE=0
      sleep 15  # Wait for Chromium to relaunch
      continue
    fi
  fi

  sleep 10  # Poll every 10 seconds
done
