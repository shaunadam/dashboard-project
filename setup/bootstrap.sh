#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

APT_PACKAGES=(
  git
  vim
  curl
  htop
  jq
  python3-paho-mqtt
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

  # WiFi (for Phase 2 watchdog)
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
        inactivity_timeout_seconds: 60,
        scheduled_reboot_interval_hours: 48
      },
      system: {
        reboot_flag_file: "/var/run/touchscreen-reboot-attempted",
        log_tag_touchscreen: "touchscreen-check"
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

generate_systemd_services() {
  # Touchscreen check service
  sudo tee /etc/systemd/system/touchscreen-check.service > /dev/null << EOF
[Unit]
Description=Touchscreen Detection and Auto-Reboot Service
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=${REPO_ROOT}/touchscreen/touchscreen-check.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  # MQTT listener — installed as a systemd *user* service so it runs inside
  # the graphical session and can reach the Wayland compositor (wlopm needs it).
  mkdir -p "${HOME}/.config/systemd/user"
  cat > "${HOME}/.config/systemd/user/mqtt-listener.service" << EOF
[Unit]
Description=MQTT Display Control Listener
After=default.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 ${REPO_ROOT}/mqtt/mqtt_listener.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
KillMode=mixed
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload 2>/dev/null || true
  systemctl --user enable mqtt-listener.service 2>/dev/null || true

  # WiFi ensure service — clears "user-disconnected" flag on boot
  # Runs before graphical.target so kiosk has network on launch
  sudo tee /etc/systemd/system/wifi-ensure.service > /dev/null << EOF
[Unit]
Description=Ensure WiFi is connected on boot
After=NetworkManager-wait-online.service
Wants=NetworkManager-wait-online.service
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/bin/nmcli device connect wlan0
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  # WiFi watchdog timer
  sudo tee /etc/systemd/system/wifi-watchdog.timer > /dev/null << EOF
[Unit]
Description=WiFi Watchdog Timer
After=touchscreen-check.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
EOF

  # WiFi watchdog service
  sudo tee /etc/systemd/system/wifi-watchdog.service > /dev/null << EOF
[Unit]
Description=WiFi Watchdog Check
After=network-online.target touchscreen-check.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${REPO_ROOT}/watchdog/wifi-watchdog.sh
StandardOutput=journal
StandardError=journal
EOF

  # Browser watchdog service
  sudo tee /etc/systemd/system/browser-watchdog.service > /dev/null << EOF
[Unit]
Description=Browser Idle Watchdog
After=graphical.target touchscreen-check.service
Wants=graphical.target
StartLimitBurst=5
StartLimitIntervalSec=300

[Service]
Type=simple
ExecStart=${REPO_ROOT}/watchdog/browser-watchdog.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
User=${USER}
Environment=DISPLAY=:0

[Install]
WantedBy=graphical.target
EOF

  # Scheduled reboot timer
  local reboot_hours
  reboot_hours=$(jq -r '.browser.scheduled_reboot_interval_hours // 48' "${REPO_ROOT}/config.json" 2>/dev/null || echo "48")

  sudo tee /etc/systemd/system/scheduled-reboot.timer > /dev/null << EOF
[Unit]
Description=Scheduled Soft Reboot Timer

[Timer]
OnBootSec=${reboot_hours}h
AccuracySec=1h

[Install]
WantedBy=timers.target
EOF

  # Scheduled reboot service
  sudo tee /etc/systemd/system/scheduled-reboot.service > /dev/null << EOF
[Unit]
Description=Scheduled Soft Reboot

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl reboot
StandardOutput=journal
StandardError=journal
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable touchscreen-check.service
  sudo systemctl enable wifi-ensure.service
  sudo systemctl enable wifi-watchdog.timer
  sudo systemctl enable browser-watchdog.service
  sudo systemctl enable scheduled-reboot.timer
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
  generate_systemd_services
  enable_persistent_journal
  make_scripts_executable
  log "Bootstrap complete. Reboot recommended."
}

main "$@"
