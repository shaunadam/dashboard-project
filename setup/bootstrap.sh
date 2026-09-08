#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Runtime dependencies. vim/htop are on-Pi conveniences, not runtime deps, so
# verify.sh deliberately does not fail on them.
# NOTE: wlopm (used by display/display_control.py) is not packaged for Raspberry
# Pi OS and must be installed separately; verify.sh checks for it.
APT_PACKAGES=(
  git
  vim
  curl
  htop
  jq
  python3-paho-mqtt
  unclutter
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

install_mqtt_dependencies() {
  log "MQTT client library installed via apt (python3-paho-mqtt)."
}

configure_secrets() {
  local secrets_file="${REPO_ROOT}/secrets.json"
  local legacy_config="${REPO_ROOT}/config.json.legacy"

  if [ -f "${secrets_file}" ]; then
    log "Secrets already exist at ${secrets_file}, skipping configuration."
    log "To reconfigure, delete ${secrets_file} and re-run bootstrap."
    return
  fi

  # Upgrading from the single-file layout: pull the credentials across rather
  # than making someone retype them. See setup/migrate-secrets.sh.
  if [ -f "${legacy_config}" ]; then
    log "Found ${legacy_config} — migrating credentials from it."
    bash "${SCRIPT_DIR}/migrate-secrets.sh" "${legacy_config}"
    return
  fi

  log ""
  log "=== Dashboard Secrets ==="
  log "Non-secret settings live in the tracked config.json; edit that in git."
  log "Only credentials are asked for here."
  log ""

  read -rp "MQTT Username: " mqtt_username
  read -rsp "MQTT Password: " mqtt_password
  echo ""

  # WiFi (used by watchdog/wifi-watchdog.sh to reapply credentials on failure)
  read -rp "WiFi SSID: " wifi_ssid
  read -rsp "WiFi Password: " wifi_password
  echo ""

  # Generate secrets.json using jq for proper JSON escaping
  jq -n \
    --arg mqtt_username "$mqtt_username" \
    --arg mqtt_password "$mqtt_password" \
    --arg wifi_ssid "$wifi_ssid" \
    --arg wifi_password "$wifi_password" \
    '{
      mqtt: {
        username: $mqtt_username,
        password: $mqtt_password
      },
      wifi: {
        ssid: $wifi_ssid,
        password: $wifi_password
      }
    }' > "${secrets_file}"

  chmod 600 "${secrets_file}"
  log "Secrets saved to ${secrets_file}"
}

generate_autostart_entry() {
  local dest="${HOME}/.config/autostart/kiosk.desktop"
  mkdir -p "$(dirname "${dest}")"

  cat > "${dest}" << EOF
[Desktop Entry]
Type=Application
Name=Kiosk
Exec=${REPO_ROOT}/kiosk/kiosk.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF

  log "Autostart entry installed to ${dest}"
}

ensure_state_directory() {
  # Persistent (non-tmpfs) home for reboot-attempt flag files. /var/run is
  # tmpfs and clears every boot, which defeats the boot-loop protection these
  # flags exist for.
  sudo mkdir -p /var/lib/dashboard-project
  sudo chmod 755 /var/lib/dashboard-project
  log "Persistent state directory ready at /var/lib/dashboard-project"
}

generate_systemd_services() {
  # shellcheck source=./systemd-units.sh
  source "${SCRIPT_DIR}/systemd-units.sh"
  install_systemd_units
  log "Systemd services installed and enabled"
}

enable_persistent_journal() {
  # Create /var/log/journal so systemd-journald persists logs across reboots.
  # systemd defaults to persistent storage when this directory exists.
  sudo mkdir -p /var/log/journal
  log "Persistent journald storage enabled"
}

make_scripts_executable() {
  chmod +x "${REPO_ROOT}/kiosk/kiosk.sh"
  chmod +x "${REPO_ROOT}/touchscreen/touchscreen-check.sh"
  chmod +x "${REPO_ROOT}/mqtt/mqtt_listener.py"
  chmod +x "${REPO_ROOT}/display/display_control.py"
  chmod +x "${REPO_ROOT}/watchdog/wifi-watchdog.sh"
  chmod +x "${REPO_ROOT}/watchdog/browser-watchdog.sh"
  chmod +x "${SCRIPT_DIR}/"*.sh
}

main() {
  log "Starting bootstrap..."
  ensure_apt_packages
  install_mqtt_dependencies
  configure_secrets
  generate_autostart_entry
  ensure_state_directory
  generate_systemd_services
  enable_persistent_journal
  make_scripts_executable
  log "Bootstrap complete. Reboot recommended."
}

main "$@"
