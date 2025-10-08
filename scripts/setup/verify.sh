#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AUTOSTART_DEST="${HOME}/.config/autostart/kiosk.desktop"
AUTOSTART_TEMPLATE="${REPO_ROOT}/config/autostart/kiosk.desktop"

issues=()

log() {
  echo "[verify] $*"
}

require_command() {
  local cmd
  cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    issues+=("Missing command: ${cmd}")
  else
    log "Found command: ${cmd}"
  fi
}

require_python_module() {
  local module
  module="$1"
  if ! python3 -c "import ${module}" >/dev/null 2>&1; then
    issues+=("Missing Python module: ${module}")
  else
    log "Python module available: ${module}"
  fi
}

check_docker() {
  local install_docker_flag
  install_docker_flag=${INSTALL_DOCKER:-0}
  if [[ "${install_docker_flag}" != "1" ]]; then
    log "Docker check skipped (INSTALL_DOCKER=${install_docker_flag})."
    return
  fi

  require_command docker
}

check_autostart() {
  local rendered
  rendered="$(mktemp)"
  sed "s#__REPO_ROOT__#${REPO_ROOT}#g" "${AUTOSTART_TEMPLATE}" > "${rendered}"

  if [[ ! -f "${AUTOSTART_DEST}" ]]; then
    issues+=("Autostart entry missing: ${AUTOSTART_DEST}")
  elif ! cmp -s "${rendered}" "${AUTOSTART_DEST}"; then
    issues+=("Autostart entry differs from template: ${AUTOSTART_DEST}")
  else
    log "Autostart entry matches template."
  fi

  rm -f "${rendered}"
}

check_kiosk_script() {
  if [[ -x "${REPO_ROOT}/kiosk.sh" ]]; then
    log "kiosk.sh is executable."
  else
    issues+=("kiosk.sh is not executable; run chmod +x ${REPO_ROOT}/kiosk.sh")
  fi
}

main() {
  log "Starting verification..."
  require_command chromium-browser
  require_command unclutter
  require_command xdotool
  require_command git
  require_command curl
  require_command htop
  require_command python3
  check_docker
  require_python_module gpiozero
  require_python_module RPi.GPIO
  check_autostart
  check_kiosk_script

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
