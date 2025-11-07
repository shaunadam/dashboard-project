#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
AUTOSTART_DEST="${HOME}/.config/autostart/kiosk.desktop"
AUTOSTART_TEMPLATE="${REPO_ROOT}/config/autostart/kiosk.desktop"
APT_PACKAGES=(
  git
  vim
  curl
  htop
  python3-pip
  unclutter
  xdotool
  python3-gpiozero
  python3-rpi.gpio
  chromium-browser
)

log() {
  echo "[bootstrap] $*"
}

ensure_apt_packages() {
  if ! command -v apt-get >/dev/null 2>&1; then
    log "apt-get not found; skipping package installation."
    return
  fi

  log "Updating apt package index..."
  sudo apt-get update
  log "Installing required apt packages..."
  sudo apt-get install -y "${APT_PACKAGES[@]}"
}

install_docker() {
  local install_docker_flag
  install_docker_flag=${INSTALL_DOCKER:-0}

  if [[ "${install_docker_flag}" != "1" ]]; then
    log "Skipping Docker installation (INSTALL_DOCKER=${install_docker_flag})."
    return
  fi

  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed; skipping."
  else
    log "Installing Docker via convenience script..."
    local tmp_script
    tmp_script="$(mktemp)"
    curl -fsSL https://get.docker.com -o "${tmp_script}"
    sudo sh "${tmp_script}"
    rm -f "${tmp_script}"
  fi

  if command -v usermod >/dev/null 2>&1; then
    log "Ensuring ${USER} belongs to docker group..."
    sudo usermod -aG docker "${USER}"
  fi
}

sync_autostart_entry() {
  mkdir -p "$(dirname "${AUTOSTART_DEST}")"

  local rendered
  rendered="$(mktemp)"
  sed "s#__REPO_ROOT__#${REPO_ROOT}#g" "${AUTOSTART_TEMPLATE}" > "${rendered}"

  if cmp -s "${rendered}" "${AUTOSTART_DEST}" 2>/dev/null; then
    rm -f "${rendered}"
    log "Autostart entry already up to date."
  else
    log "Installing autostart entry to ${AUTOSTART_DEST}..."
    install -m 644 "${rendered}" "${AUTOSTART_DEST}"
  fi
  rm -f "${rendered}"
}

make_scripts_executable() {
  chmod +x "${REPO_ROOT}/scripts/kiosk.sh"
  chmod +x "${REPO_ROOT}/scripts/touchscreen-check.sh"
  chmod +x "${SCRIPT_DIR}/"*.sh
}

install_touchscreen_service() {
  local service_template="${REPO_ROOT}/config/systemd/touchscreen-check.service"
  local service_dest="/etc/systemd/system/touchscreen-check.service"

  if [ ! -f "${service_template}" ]; then
    log "WARNING: Touchscreen service template not found, skipping."
    return
  fi

  log "Installing touchscreen check service..."

  # Render template with actual repo path
  local rendered
  rendered="$(mktemp)"
  sed "s#__REPO_ROOT__#${REPO_ROOT}#g" "${service_template}" > "${rendered}"

  # Install to systemd
  sudo install -m 644 "${rendered}" "${service_dest}"
  rm -f "${rendered}"

  # Reload systemd and enable service
  sudo systemctl daemon-reload
  sudo systemctl enable touchscreen-check.service

  log "Touchscreen check service enabled"
}

main() {
  log "Starting bootstrap tasks..."
  ensure_apt_packages
  install_docker
  sync_autostart_entry
  install_touchscreen_service
  make_scripts_executable
  log "Bootstrap complete. Reboot may be required for group membership changes."
}

main "$@"
