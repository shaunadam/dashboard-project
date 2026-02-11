#!/bin/bash
set -euo pipefail

# WiFi Watchdog - Detects network failures and recovers automatically.
# Uses multi-stage network validation and staged recovery with nmcli.
# Flag-file boot-loop protection prevents infinite reboot loops.
# All configurable values are loaded from config.json via lib/config.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/lib/config.sh"

# Load configuration (required values)
WIFI_SSID="$(cfg_require '.wifi.ssid')"
WIFI_PASSWORD="$(cfg_require '.wifi.password')"
DASHBOARD_URL="$(cfg_require '.dashboard.url')"

# Load configuration (optional values with sensible defaults)
FLAG_FILE="$(cfg_get '.system.reboot_flag_file_wifi')"
FLAG_FILE="${FLAG_FILE:-/var/run/wifi-reboot-attempted}"
LOG_TAG="$(cfg_get '.system.log_tag_wifi')"
LOG_TAG="${LOG_TAG:-wifi-watchdog}"

log_message() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

# Multi-stage network validation.
# Returns 0 if ANY stage passes (network is working).
# Returns 1 only if ALL stages fail.
check_network() {
  # Stage 1: Ping default gateway (local network up?)
  local gateway
  gateway=$(ip route | grep default | awk '{print $3}' | head -1)
  if [ -n "$gateway" ] && ping -c 1 -W 5 "$gateway" &>/dev/null; then
    log_message "Network check: gateway ping OK ($gateway)"
    return 0
  fi

  # Stage 2: Ping public DNS (internet reachable?)
  if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
    log_message "Network check: public DNS ping OK"
    return 0
  fi

  # Stage 3: DNS resolution (DNS working?)
  if host google.com &>/dev/null; then
    log_message "Network check: DNS resolution OK"
    return 0
  fi

  # Stage 4: HTTP check to dashboard (actual service reachable?)
  if curl --max-time 10 --silent --output /dev/null "$DASHBOARD_URL"; then
    log_message "Network check: HTTP dashboard OK"
    return 0
  fi

  return 1  # All checks failed
}

# Apply WiFi credentials from config.json via nmcli.
apply_wifi_credentials() {
  log_message "Applying WiFi credentials from config for SSID: $WIFI_SSID"

  # Check if connection profile already exists
  if nmcli -t -f NAME connection show | grep -q "^${WIFI_SSID}$"; then
    # Update existing connection with credentials from config
    sudo nmcli connection modify "$WIFI_SSID" \
      wifi-sec.key-mgmt wpa-psk \
      wifi-sec.psk "$WIFI_PASSWORD"
    log_message "Updated existing connection profile for $WIFI_SSID"
  else
    # Create new connection profile
    sudo nmcli connection add type wifi con-name "$WIFI_SSID" \
      ifname wlan0 ssid "$WIFI_SSID"
    sudo nmcli connection modify "$WIFI_SSID" \
      wifi-sec.key-mgmt wpa-psk \
      wifi-sec.psk "$WIFI_PASSWORD"
    log_message "Created new connection profile for $WIFI_SSID"
  fi

  # Bring connection up
  sudo nmcli connection up "$WIFI_SSID"
}

# Staged recovery: try least-disruptive actions first, reboot as last resort.
recover_network() {
  # Stage 1: nmcli down/up cycle for existing connection
  log_message "Recovery Stage 1: nmcli connection down/up cycle"
  sudo nmcli connection down "$WIFI_SSID" 2>/dev/null || true
  sleep 2
  sudo nmcli connection up "$WIFI_SSID" 2>/dev/null || true
  sleep 15
  if check_network; then
    log_message "Recovery Stage 1 succeeded: network restored after connection cycle"
    return 0
  fi

  # Stage 2: Apply credentials from config and reconnect
  log_message "Recovery Stage 2: applying WiFi credentials from config"
  apply_wifi_credentials 2>/dev/null || true
  sleep 15
  if check_network; then
    log_message "Recovery Stage 2 succeeded: network restored after credential apply"
    return 0
  fi

  # Stage 3: Restart NetworkManager entirely
  log_message "Recovery Stage 3: restarting NetworkManager"
  sudo systemctl restart NetworkManager
  sleep 15
  if check_network; then
    log_message "Recovery Stage 3 succeeded: network restored after NetworkManager restart"
    return 0
  fi

  # All recovery stages failed -- consider reboot with flag-file protection
  log_message "All recovery stages failed"

  if [ -f "$FLAG_FILE" ]; then
    log_message "ERROR: Reboot already attempted but network still down"
    log_message "Manual intervention required - check WiFi router and Pi network config"
    exit 1
  fi

  # Set flag and reboot
  touch "$FLAG_FILE"
  log_message "REBOOTING: Network recovery failed, attempting system reboot..."
  systemctl reboot
}

# --- Main Logic ---

if check_network; then
  # Network is healthy
  log_message "Network OK"

  # Clear flag file if it exists (clean slate for next failure)
  if [ -f "$FLAG_FILE" ]; then
    rm -f "$FLAG_FILE"
    log_message "Cleared WiFi reboot flag file"
  fi

  exit 0
fi

# Network check failed -- begin recovery
log_message "WARNING: Network check failed - all 4 stages returned failure"
recover_network

# If recovery succeeded (didn't reboot), signal browser to reload
# Use world-writable permissions so browser-watchdog (running as user) can delete it
touch /tmp/wifi-recovered
chmod 666 /tmp/wifi-recovered
log_message "Network recovered - signaled browser reload via /tmp/wifi-recovered"
