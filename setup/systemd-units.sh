#!/usr/bin/env bash
# Shared systemd unit definitions for mqtt-listener (user service), wifi-ensure,
# wifi-watchdog, browser-watchdog, and scheduled-reboot.
#
# Sourced by bootstrap.sh (initial install) and switch-branch.sh (unit files
# embed REPO_ROOT, so they must be regenerated whenever the checked-out path
# could differ). Callers must set REPO_ROOT before sourcing.

# Units this project used to install but no longer does. Regenerating the unit
# files can't remove a stale one, and the Pi only ever updates itself via
# git pull, so retiring a unit has to be an explicit step here.
OBSOLETE_SYSTEM_UNITS=(
  touchscreen-check.service
)

# Files left behind by retired units.
OBSOLETE_STATE_FILES=(
  /var/lib/dashboard-project/touchscreen-reboot-attempted
)

remove_obsolete_units() {
  local unit
  for unit in "${OBSOLETE_SYSTEM_UNITS[@]}"; do
    if [[ -f "/etc/systemd/system/${unit}" ]]; then
      echo "[systemd-units] Removing retired unit: ${unit}"
      sudo systemctl disable --now "${unit}" >/dev/null 2>&1 || true
      sudo rm -f "/etc/systemd/system/${unit}"
    fi
  done

  local state_file
  for state_file in "${OBSOLETE_STATE_FILES[@]}"; do
    if [[ -e "${state_file}" ]]; then
      echo "[systemd-units] Removing stale state file: ${state_file}"
      sudo rm -f "${state_file}"
    fi
  done
}

install_systemd_units() {
  local reboot_hours
  reboot_hours=$(jq -r '.browser.scheduled_reboot_interval_hours // 48' "${REPO_ROOT}/config.json" 2>/dev/null || echo "48")

  remove_obsolete_units

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
After=network-online.target
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
After=graphical.target
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
  sudo systemctl enable wifi-ensure.service
  sudo systemctl enable wifi-watchdog.timer
  sudo systemctl enable browser-watchdog.service
  sudo systemctl enable scheduled-reboot.timer
}
