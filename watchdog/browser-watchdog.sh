#!/bin/bash
set -euo pipefail

# Browser Watchdog - Returns to home dashboard after inactivity timeout.
# Monitors idle time via Chrome DevTools Protocol (CDP) JavaScript injection
# and navigates browser back to the configured dashboard URL after timeout.
# Also detects WiFi recovery signal to reload dashboard after network restoration.
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

# Convert timeout to milliseconds for CDP idle comparison
IDLE_TIMEOUT_MS=$((INACTIVITY_TIMEOUT * 1000))

# WiFi recovery signal file (touched by wifi-watchdog.sh after successful recovery)
WIFI_RECOVERY_SIGNAL="/tmp/wifi-recovered"

# Browser control helper for CDP navigation and idle tracking
BROWSER_CONTROL="$REPO_ROOT/lib/browser_control.py"

# Track whether idle tracker has been injected
TRACKER_INJECTED=false

log_message() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

# navigate_to_dashboard - Navigate browser to the configured dashboard URL via CDP.
navigate_to_dashboard() {
  if python3 "$BROWSER_CONTROL" navigate "$DASHBOARD_URL" 2>/dev/null; then
    log_message "Navigated to dashboard via CDP: $DASHBOARD_URL"
    # Re-inject tracker on the new page (addScriptToEvaluateOnNewDocument handles
    # future navigations, but explicit inject ensures it's active now)
    sleep 2
    python3 "$BROWSER_CONTROL" inject-idle-tracker 2>/dev/null || true
  else
    log_message "CDP navigation failed — Chromium may not be ready"
  fi
}

# inject_tracker - Inject the idle tracking JavaScript via CDP.
# Called once after Chromium is ready, persists across page navigations.
inject_tracker() {
  if python3 "$BROWSER_CONTROL" inject-idle-tracker 2>/dev/null; then
    TRACKER_INJECTED=true
    log_message "Idle tracker injected via CDP"
    return 0
  fi
  return 1
}

log_message "Browser watchdog started (idle timeout: ${INACTIVITY_TIMEOUT}s / ${IDLE_TIMEOUT_MS}ms)"

while true; do
  # Check WiFi recovery signal
  if [ -f "$WIFI_RECOVERY_SIGNAL" ]; then
    log_message "WiFi recovery detected, navigating to dashboard"
    rm -f "$WIFI_RECOVERY_SIGNAL" 2>/dev/null || true
    navigate_to_dashboard
    sleep 10  # Brief pause after navigation
    continue
  fi

  # Ensure idle tracker is injected (retry until Chromium is ready)
  if [ "$TRACKER_INJECTED" = false ]; then
    if inject_tracker; then
      log_message "CDP connection established"
    else
      log_message "Waiting for CDP connection to Chromium..."
      sleep 10
      continue
    fi
  fi

  # Check idle time via CDP
  IDLE_MS=$(python3 "$BROWSER_CONTROL" get-idle-ms 2>/dev/null || echo "-1")

  # -1 means tracker not found (page navigated and lost it) — re-inject
  if [ "$IDLE_MS" = "-1" ]; then
    log_message "Idle tracker lost, re-injecting"
    python3 "$BROWSER_CONTROL" inject-idle-tracker 2>/dev/null || true
    sleep 10
    continue
  fi

  if [ "$IDLE_MS" -gt "$IDLE_TIMEOUT_MS" ]; then
    log_message "Idle timeout reached (${IDLE_MS}ms > ${IDLE_TIMEOUT_MS}ms), navigating to dashboard"
    navigate_to_dashboard
    # Wait before checking again to avoid rapid-fire navigation
    sleep "$INACTIVITY_TIMEOUT"
  fi

  sleep 10  # Check every 10 seconds
done
