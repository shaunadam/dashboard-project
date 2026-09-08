#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

issues=()

log() {
  echo "[verify] $*"
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    issues+=("Missing command: ${cmd}")
  else
    log "Found command: ${cmd}"
  fi
}

require_python_module() {
  local module="$1"
  if ! python3 -c "import ${module}" >/dev/null 2>&1; then
    issues+=("Missing Python module: ${module}")
  else
    log "Python module available: ${module}"
  fi
}

check_config() {
  local config="${REPO_ROOT}/config.json"
  if [[ ! -f "${config}" ]]; then
    issues+=("config.json not found; it is tracked in git — re-check out the repo")
    return
  fi
  # Validate JSON syntax
  if ! jq empty "${config}" 2>/dev/null; then
    issues+=("config.json is not valid JSON")
    return
  fi
  # Check required keys
  local required_keys=(".dashboard.url" ".mqtt.broker" ".mqtt.port" ".system.reboot_flag_file_wifi" ".system.wifi_recovery_signal_file")
  for key in "${required_keys[@]}"; do
    if [[ "$(jq -r "${key} // empty" "${config}")" == "" ]]; then
      issues+=("config.json missing required key: ${key}")
    fi
  done

  # config.json is committed, so credentials must never appear in it.
  local secret_keys=(".mqtt.username" ".mqtt.password" ".wifi.ssid" ".wifi.password")
  for key in "${secret_keys[@]}"; do
    if [[ "$(jq -r "${key} // empty" "${config}")" != "" ]]; then
      issues+=("SECURITY: ${key} is present in the tracked config.json — it belongs in secrets.json")
    fi
  done

  log "config.json validated."
}

check_secrets() {
  local secrets="${REPO_ROOT}/secrets.json"
  if [[ ! -f "${secrets}" ]]; then
    issues+=("secrets.json not found; run bootstrap.sh or setup/migrate-secrets.sh")
    return
  fi
  if ! jq empty "${secrets}" 2>/dev/null; then
    issues+=("secrets.json is not valid JSON")
    return
  fi

  local required_keys=(".mqtt.username" ".mqtt.password" ".wifi.ssid" ".wifi.password")
  for key in "${required_keys[@]}"; do
    if [[ "$(jq -r "${key} // empty" "${secrets}")" == "" ]]; then
      issues+=("secrets.json missing required key: ${key}")
    fi
  done

  # The whole point of the split — make sure git really is ignoring it.
  if git -C "${REPO_ROOT}" check-ignore -q secrets.json 2>/dev/null; then
    log "secrets.json is git-ignored."
  else
    issues+=("SECURITY: secrets.json is not git-ignored — check .gitignore before committing")
  fi

  local mode
  mode="$(stat -c '%a' "${secrets}" 2>/dev/null || echo "")"
  if [[ -n "${mode}" && "${mode}" != "600" ]]; then
    issues+=("secrets.json is mode ${mode}; expected 600 (chmod 600 ${secrets})")
  fi

  log "secrets.json validated."
}

check_libraries() {
  if [[ ! -f "${REPO_ROOT}/lib/config.sh" ]]; then
    issues+=("lib/config.sh not found")
  fi
  if [[ ! -f "${REPO_ROOT}/lib/config.py" ]]; then
    issues+=("lib/config.py not found")
  fi
  log "Library files present."
}

check_autostart() {
  local dest="${HOME}/.config/autostart/kiosk.desktop"
  if [[ ! -f "${dest}" ]]; then
    issues+=("Autostart entry missing: ${dest}")
    return
  fi
  if ! grep -q "kiosk/kiosk.sh" "${dest}"; then
    issues+=("Autostart entry does not reference kiosk/kiosk.sh")
    return
  fi
  log "Autostart entry OK."
}

check_kiosk_script() {
  if [[ -x "${REPO_ROOT}/kiosk/kiosk.sh" ]]; then
    log "kiosk.sh is executable."
  else
    issues+=("kiosk.sh is not executable; run chmod +x ${REPO_ROOT}/kiosk/kiosk.sh")
  fi
}

check_retired_units() {
  # The touchscreen was removed from this project. Catch a Pi still carrying
  # the old unit — it would fail at boot looking for a script that's gone.
  local retired=(touchscreen-check.service)
  local unit
  for unit in "${retired[@]}"; do
    if systemctl list-unit-files "${unit}" 2>/dev/null | grep -q "${unit}"; then
      issues+=("Retired unit still installed: ${unit} — run setup/switch-branch.sh (or bootstrap.sh) to remove it")
    fi
  done
  log "No retired units installed."
}

check_mqtt_listener() {
  if [[ ! -f "${REPO_ROOT}/mqtt/mqtt_listener.py" ]]; then
    issues+=("mqtt_listener.py not found")
    return
  fi

  if [[ ! -x "${REPO_ROOT}/mqtt/mqtt_listener.py" ]]; then
    issues+=("mqtt_listener.py is not executable")
  fi

  # mqtt-listener is a systemd *user* service (it needs the graphical session
  # to reach the Wayland compositor for wlopm), so check the user manager.
  if systemctl --user is-enabled mqtt-listener.service >/dev/null 2>&1; then
    log "mqtt-listener.service (user) is enabled."
  else
    issues+=("mqtt-listener.service is not enabled; run bootstrap.sh or: systemctl --user enable mqtt-listener.service")
  fi
}

check_display_control() {
  if [[ ! -f "${REPO_ROOT}/display/display_control.py" ]]; then
    issues+=("display_control.py not found")
    return
  fi

  if [[ ! -x "${REPO_ROOT}/display/display_control.py" ]]; then
    issues+=("display_control.py is not executable; run chmod +x ${REPO_ROOT}/display/display_control.py")
  fi

  log "display_control.py OK."
}

check_wifi_watchdog() {
  if [[ ! -f "${REPO_ROOT}/watchdog/wifi-watchdog.sh" ]]; then
    issues+=("wifi-watchdog.sh not found")
    return
  fi
  if [[ ! -x "${REPO_ROOT}/watchdog/wifi-watchdog.sh" ]]; then
    issues+=("wifi-watchdog.sh is not executable")
  fi
  if systemctl is-enabled wifi-watchdog.timer >/dev/null 2>&1; then
    log "wifi-watchdog.timer is enabled."
  else
    issues+=("wifi-watchdog.timer is not enabled; run bootstrap.sh")
  fi
}

check_browser_watchdog() {
  if [[ ! -f "${REPO_ROOT}/watchdog/browser-watchdog.sh" ]]; then
    issues+=("browser-watchdog.sh not found")
    return
  fi
  if [[ ! -x "${REPO_ROOT}/watchdog/browser-watchdog.sh" ]]; then
    issues+=("browser-watchdog.sh is not executable")
  fi
  if systemctl is-enabled browser-watchdog.service >/dev/null 2>&1; then
    log "browser-watchdog.service is enabled."
  else
    issues+=("browser-watchdog.service is not enabled; run bootstrap.sh")
  fi
}

check_scheduled_reboot() {
  if systemctl is-enabled scheduled-reboot.timer >/dev/null 2>&1; then
    log "scheduled-reboot.timer is enabled."
  else
    issues+=("scheduled-reboot.timer is not enabled; run bootstrap.sh")
  fi
}

main() {
  log "Starting verification..."
  require_command chromium-browser
  require_command unclutter
  require_command wlopm
  require_command git
  require_command curl
  require_command python3
  require_command jq
  require_python_module paho.mqtt.client
  check_config
  check_secrets
  check_libraries
  check_autostart
  check_kiosk_script
  check_retired_units
  check_mqtt_listener
  check_display_control
  check_wifi_watchdog
  check_browser_watchdog
  check_scheduled_reboot

  if [[ ${#issues[@]} -eq 0 ]]; then
    log "All checks passed."
    exit 0
  fi

  log "Encountered issues:"
  for issue in "${issues[@]}"; do
    echo " - ${issue}"
  done
  exit 1
}

main "$@"
