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
    issues+=("config.json not found; run bootstrap.sh")
    return
  fi
  # Validate JSON syntax
  if ! jq empty "${config}" 2>/dev/null; then
    issues+=("config.json is not valid JSON")
    return
  fi
  # Check required keys
  local required_keys=(".dashboard.url" ".mqtt.broker" ".mqtt.port" ".touchscreen.usb_device_id")
  for key in "${required_keys[@]}"; do
    if [[ "$(jq -r "${key} // empty" "${config}")" == "" ]]; then
      issues+=("config.json missing required key: ${key}")
    fi
  done
  log "config.json validated."
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

check_touchscreen_service() {
  if [[ ! -f "${REPO_ROOT}/touchscreen/touchscreen-check.sh" ]]; then
    issues+=("touchscreen-check.sh not found")
    return
  fi

  if [[ ! -x "${REPO_ROOT}/touchscreen/touchscreen-check.sh" ]]; then
    issues+=("touchscreen-check.sh is not executable")
  fi

  if systemctl is-enabled touchscreen-check.service >/dev/null 2>&1; then
    log "touchscreen-check.service is enabled."
  else
    issues+=("touchscreen-check.service is not enabled; run bootstrap.sh or: sudo systemctl enable touchscreen-check.service")
  fi
}

check_mqtt_listener() {
  if [[ ! -f "${REPO_ROOT}/mqtt/mqtt_listener.py" ]]; then
    issues+=("mqtt_listener.py not found")
    return
  fi

  if [[ ! -x "${REPO_ROOT}/mqtt/mqtt_listener.py" ]]; then
    issues+=("mqtt_listener.py is not executable")
  fi

  if systemctl is-enabled mqtt-listener.service >/dev/null 2>&1; then
    log "mqtt-listener.service is enabled."
  else
    issues+=("mqtt-listener.service is not enabled; run bootstrap.sh or: sudo systemctl enable mqtt-listener.service")
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

main() {
  log "Starting verification..."
  require_command chromium-browser
  require_command unclutter
  require_command xdotool
  require_command onboard
  require_command git
  require_command curl
  require_command htop
  require_command python3
  require_command jq
  require_python_module gpiozero
  require_python_module RPi.GPIO
  require_python_module paho.mqtt.client
  check_config
  check_libraries
  check_autostart
  check_kiosk_script
  check_touchscreen_service
  check_mqtt_listener
  check_display_control

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
