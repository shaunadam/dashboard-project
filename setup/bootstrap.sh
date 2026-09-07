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

configure_dashboard() {
  local config_file="${REPO_ROOT}/config.json"

  if [ -f "${config_file}" ]; then
    log "Config already exists at ${config_file}, skipping configuration."
    log "To reconfigure, delete ${config_file} and re-run bootstrap."
    return
  fi

  log ""
  log "=== Dashboard Configuration ==="
  log "Enter your configuration values (press Enter for defaults):"
  log ""

  # Dashboard
  read -rp "Dashboard URL [http://192.168.68.75:8123]: " dashboard_url
  dashboard_url="${dashboard_url:-http://192.168.68.75:8123}"

  # MQTT
  read -rp "MQTT Broker IP/hostname: " mqtt_broker
  read -rp "MQTT Port [1883]: " mqtt_port
  mqtt_port="${mqtt_port:-1883}"
  read -rp "MQTT Username: " mqtt_username
  read -rsp "MQTT Password: " mqtt_password
  echo ""

  # Touchscreen
  read -rp "Touchscreen USB ID [222a:0001]: " ts_usb_id
  ts_usb_id="${ts_usb_id:-222a:0001}"

  # Chromium
  read -rp "Chromium user data dir [${HOME}/.config/chromium-kiosk]: " chromium_dir
  chromium_dir="${chromium_dir:-${HOME}/.config/chromium-kiosk}"

  # WiFi (used by watchdog/wifi-watchdog.sh to reapply credentials on failure)
  read -rp "WiFi SSID: " wifi_ssid
  read -rsp "WiFi Password: " wifi_password
  echo ""

  # Generate config.json using jq for proper JSON escaping
  jq -n \
    --arg dashboard_url "$dashboard_url" \
    --arg mqtt_broker "$mqtt_broker" \
    --argjson mqtt_port "$mqtt_port" \
    --arg mqtt_username "$mqtt_username" \
    --arg mqtt_password "$mqtt_password" \
    --arg ts_usb_id "$ts_usb_id" \
    --arg chromium_dir "$chromium_dir" \
    --arg wifi_ssid "$wifi_ssid" \
    --arg wifi_password "$wifi_password" \
    '{
      dashboard: { url: $dashboard_url },
      mqtt: {
        broker: $mqtt_broker,
        port: $mqtt_port,
        username: $mqtt_username,
        password: $mqtt_password,
        client_id: "dashboard-display-pi",
        topics: {
          command: "dashboard/display/command",
          status: "dashboard/display/status",
          availability: "dashboard/display/availability"
        },
        heartbeat_interval_seconds: 60
      },
      display: { wayland_display: "wayland-0" },
      touchscreen: {
        usb_device_id: $ts_usb_id,
        detection_wait_seconds: 60
      },
      kiosk: {
        desktop_load_wait_seconds: 10,
        onboard_size: "800x300",
        user_data_dir: $chromium_dir
      },
      wifi: {
        ssid: $wifi_ssid,
        password: $wifi_password
      },
      home_assistant: {
        auth_method: "trusted_network"
      },
      browser: {
        inactivity_timeout_seconds: 300,
        scheduled_reboot_interval_hours: 48
      },
      system: {
        reboot_flag_file: "/var/lib/dashboard-project/touchscreen-reboot-attempted",
        reboot_flag_file_wifi: "/var/lib/dashboard-project/wifi-reboot-attempted",
        wifi_recovery_signal_file: "/tmp/wifi-recovered",
        log_tag_touchscreen: "touchscreen-check",
        log_tag_kiosk: "kiosk",
        log_tag_wifi: "wifi-watchdog",
        log_tag_browser: "browser-watchdog"
      }
    }' > "${config_file}"

  chmod 600 "${config_file}"
  log "Configuration saved to ${config_file}"
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
  configure_dashboard
  generate_autostart_entry
  ensure_state_directory
  generate_systemd_services
  enable_persistent_journal
  make_scripts_executable
  log "Bootstrap complete. Reboot recommended."
}

main "$@"
