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
  onboard
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
  chmod +x "${REPO_ROOT}/scripts/mqtt_listener.py"
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

install_mqtt_dependencies() {
  log "Installing MQTT client library (paho-mqtt)..."
 # pip3 install --user paho-mqtt
}

configure_mqtt() {
  local mqtt_config="${REPO_ROOT}/config/mqtt.json"
  local mqtt_template="${REPO_ROOT}/config/mqtt.json.template"

  if [ -f "${mqtt_config}" ]; then
    log "MQTT config already exists at ${mqtt_config}, skipping configuration."
    log "To reconfigure, delete ${mqtt_config} and re-run bootstrap."
    return
  fi

  if [ ! -f "${mqtt_template}" ]; then
    log "WARNING: MQTT config template not found, skipping MQTT configuration."
    return
  fi

  log ""
  log "=== MQTT Configuration ==="
  log "Enter your Home Assistant MQTT broker details:"
  log ""

  read -rp "MQTT Broker IP/hostname: " mqtt_broker
  read -rp "MQTT Port [1883]: " mqtt_port
  mqtt_port="${mqtt_port:-1883}"
  read -rp "MQTT Username: " mqtt_username
  read -rsp "MQTT Password: " mqtt_password
  echo ""

  # Render template
  sed -e "s#__MQTT_BROKER__#${mqtt_broker}#g" \
      -e "s#__MQTT_USERNAME__#${mqtt_username}#g" \
      -e "s#__MQTT_PASSWORD__#${mqtt_password}#g" \
      "${mqtt_template}" | \
  sed "s#1883#${mqtt_port}#g" > "${mqtt_config}"

  chmod 600 "${mqtt_config}"
  log "MQTT configuration saved to ${mqtt_config}"
}

install_mqtt_listener_service() {
  local service_template="${REPO_ROOT}/config/systemd/mqtt-listener.service"
  local service_dest="/etc/systemd/system/mqtt-listener.service"

  if [ ! -f "${service_template}" ]; then
    log "WARNING: MQTT listener service template not found, skipping."
    return
  fi

  log "Installing MQTT listener service..."

  # Render template with actual repo path
  local rendered
  rendered="$(mktemp)"
  sed "s#__REPO_ROOT__#${REPO_ROOT}#g" "${service_template}" > "${rendered}"

  # Install to systemd
  sudo install -m 644 "${rendered}" "${service_dest}"
  rm -f "${rendered}"

  # Reload systemd and enable service
  sudo systemctl daemon-reload
  sudo systemctl enable mqtt-listener.service

  log "MQTT listener service enabled"
  log "Start it with: sudo systemctl start mqtt-listener.service"
}

main() {
  log "Starting bootstrap tasks..."
  ensure_apt_packages
  install_docker
  sync_autostart_entry
  install_touchscreen_service
  install_mqtt_dependencies
  configure_mqtt
  install_mqtt_listener_service
  make_scripts_executable
  log "Bootstrap complete. Reboot may be required for group membership changes."
}

main "$@"
