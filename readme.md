# Family Chore Dashboard

A wall-mounted touchscreen dashboard for family chore management, integrated with Home Assistant.

## Hardware

- **Raspberry Pi 4** (Model B)
- **15" USB Touchscreen Display** (ILITEK USB controller)
- **MicroSD Card** (bootable system)

### Touchscreen Cold Boot Issue

The USB touchscreen requires a warm boot to initialize properly:
- **Cold boot** (power cycle): Touchscreen USB controller doesn't enumerate in time
- **Warm boot** (reboot): Touchscreen initializes correctly

**Automatic Recovery:**
The system includes `touchscreen-check.service` which:
1. Waits 60 seconds after boot for hardware initialization
2. Checks if touchscreen (222a:0001) is detected
3. Performs ONE automatic reboot if missing (prevents infinite loops)
4. After reboot, touchscreen works normally

**What this means:**
- First boot after power loss takes ~2-3 minutes (includes auto-reboot)
- Normal reboots (`sudo reboot`) work immediately
- No manual intervention required

### Operating System
- **Raspberry Pi OS with Desktop** (64-bit)
- Hostname: `dashboard.local`
- Auto-login enabled for kiosk mode

### Core Software
- **Chromium Browser** - Kiosk mode display
- **Python 3** - For automation scripts and sensor integration
- **Git** - Version control
- **VNC** - Remote desktop access

### Python Libraries
- `gpiozero` - GPIO sensor control
- `RPi.GPIO` - Low-level GPIO access
- `paho-mqtt` - MQTT client for Home Assistant integration

### Utilities
- `unclutter` - Hides mouse cursor when idle
- `xdotool` - Simulates keyboard/mouse input for automation
- `onboard` - On-screen keyboard for touchscreen input
- `vim`, `curl`, `htop` - Standard utilities

## Home Assistant Integration

### Infrastructure
- **Home Assistant VM** running on Ubuntu Desktop (basement server, not dashboard)
- **MQTT Broker** running on Home Assistant server for device communication

### Integrations
- **Kids Chores Custom Integration** ([ad-ha/kidschores-ha](https://github.com/ad-ha/kidschores-ha))
- **Kids Chores Dashboard** ([ccpk1/kidschores-ha-dashboard](https://github.com/ccpk1/kidschores-ha-dashboard))
- **MQTT Display Control** - Turn dashboard display on/off via Home Assistant automations

## Project Structure

```
~/dashboard-project/
├── scripts/
│   ├── kiosk.sh                 # Browser startup script
│   ├── touchscreen-check.sh     # Touchscreen detection and auto-reboot
│   ├── display_control.py       # HDMI display power control
│   ├── mqtt_listener.py         # MQTT subscriber for display control
│   └── setup/
│       ├── bootstrap.sh         # Automated provisioning script
│       └── verify.sh            # Post-setup checks
├── config/
│   ├── autostart/
│   │   └── kiosk.desktop        # Autostart template
│   ├── systemd/
│   │   ├── touchscreen-check.service  # Touchscreen auto-recovery service
│   │   └── mqtt-listener.service      # MQTT display control service
│   ├── mqtt.json.template       # MQTT broker configuration template
│   └── mqtt.json                # MQTT broker configuration (created by bootstrap)
└── README.md                   # This file
```

## Installation & Setup

### Automated Bootstrap (Recommended)

Run the bootstrap script after cloning to a fresh Pi:

```bash
./scripts/setup/bootstrap.sh
```

After the script completes, confirm everything is configured correctly:

```bash
./scripts/setup/verify.sh
```

### Initial Pi Configuration

1. **Flash SD Card:**
   - Use Raspberry Pi Imager
   - Select "Raspberry Pi OS with Desktop (64-bit)"
   - Configure advanced options:
     - Enable SSH
     - Set username/password
     - Configure WiFi
     - Set hostname: `dashboard.local`
     - Set timezone and locale

2. **First Boot Setup:**
   ```bash
   ssh shaun@dashboard.local

   # Update system
   sudo apt update && sudo apt upgrade -y

   # Install essential packages
   sudo apt install -y git vim curl htop python3-pip unclutter xdotool
   sudo apt install -y python3-gpiozero python3-rpi.gpio
   ```

3. **Configure Auto-Login:**
   ```bash
   sudo raspi-config
   # System Options → Boot / Auto Login → Desktop Autologin
   # Interface Options → VNC → Enable
   ```

4. **Clone Repository:**
   ```bash
   cd ~
   git clone <your-repo-url> dashboard-project
   cd dashboard-project
   ```

### Kiosk Mode Setup

The `scripts/kiosk.sh` launcher starts Chromium in fullscreen kiosk mode on boot.

**kiosk.sh Configuration:**
```bash
#!/bin/bash

# Set display environment variable
export DISPLAY=:0

# Wait for desktop to load
sleep 10

# Hide mouse cursor
unclutter -idle 0.1 &

# Start on-screen keyboard (auto-shows on text field focus)
GDK_BACKEND=x11 onboard --size=800x300 &

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Start chromium in kiosk mode
chromium-browser \
  --kiosk \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-restore-session-state \
  --disable-web-security \
  --user-data-dir=/tmp/chromium-kiosk \
  --disable-features=TranslateUI \
  --no-first-run \
  --fast \
  --fast-start \
  --disable-default-apps \
  --password-store=basic \
  --display=:0 \
  http://192.168.1.220:8123/your-dashboard-path
```

**Key Features:**
- `export DISPLAY=:0` - Sets display environment for X utilities (unclutter, xset)
- `--password-store=basic` - Prevents keyring password prompts on boot
- `--user-data-dir=/tmp/chromium-kiosk` - Required when disabling web security
- `GDK_BACKEND=x11 onboard` - Forces X11 mode for on-screen keyboard (Wayland compatibility)

**Autostart Configuration:** (handled automatically by `scripts/setup/bootstrap.sh`)
```bash
# Create autostart directory
mkdir -p ~/.config/autostart

# Create desktop entry
cat > ~/.config/autostart/kiosk.desktop << EOF
[Desktop Entry]
Type=Application
Name=Kiosk
Exec=/home/shaun/dashboard-project/scripts/kiosk.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
```

**Make script executable:** (the bootstrap script runs this step)
```bash
chmod +x scripts/kiosk.sh
```

## Usage

### Starting/Stopping Kiosk Mode

**Automatic Start:**
- Kiosk mode launches automatically on boot via autostart

**Manual Start:**
```bash
./scripts/kiosk.sh
```

**Exit Kiosk Mode (via SSH):**
```bash
ssh user@dashboard.local
pkill chromium
```

### Touchscreen Service Management

The touchscreen auto-recovery service runs automatically on boot. To manage it manually:

```bash
# Check service status
systemctl status touchscreen-check.service

# View service logs
journalctl -u touchscreen-check.service -f

# Temporarily disable auto-reboot (e.g., for troubleshooting)
sudo systemctl disable touchscreen-check.service

# Re-enable auto-reboot
sudo systemctl enable touchscreen-check.service
```

### MQTT Display Control

The dashboard integrates with Home Assistant via MQTT for remote display power management.

#### MQTT Topics

The `mqtt-listener.service` subscribes and publishes to these topics:

- **Command Topic** (subscribe): `dashboard/display/command`
  - Accepts: `on`, `off`, `status`
- **Status Topic** (publish): `dashboard/display/status`
  - Publishes: `on`, `off`, `unknown`
- **Availability Topic** (publish): `dashboard/display/availability`
  - Publishes: `online`, `offline`

#### Service Management

```bash
# Check service status
systemctl status mqtt-listener.service

# View logs
journalctl -u mqtt-listener.service -f

# Start/stop/restart service
sudo systemctl start mqtt-listener.service
sudo systemctl stop mqtt-listener.service
sudo systemctl restart mqtt-listener.service
```

#### Manual Testing

You can test MQTT commands directly using `mosquitto_pub` (from your Home Assistant server or any MQTT client):

```bash
# Turn display on
mosquitto_pub -h <broker-ip> -u <username> -P <password> \
  -t "dashboard/display/command" -m "on"

# Turn display off
mosquitto_pub -h <broker-ip> -u <username> -P <password> \
  -t "dashboard/display/command" -m "off"

# Request status update
mosquitto_pub -h <broker-ip> -u <username> -P <password> \
  -t "dashboard/display/command" -m "status"

# Subscribe to status updates
mosquitto_sub -h <broker-ip> -u <username> -P <password> \
  -t "dashboard/display/status"
```

#### Home Assistant Automations

**Example 1: Turn display on when motion detected**

```yaml
automation:
  - alias: "Dashboard Display On - Motion Detected"
    trigger:
      - platform: state
        entity_id: binary_sensor.living_room_motion
        to: "on"
    action:
      - service: mqtt.publish
        data:
          topic: "dashboard/display/command"
          payload: "on"
```

**Example 2: Turn display off at bedtime**

```yaml
automation:
  - alias: "Dashboard Display Off - Bedtime"
    trigger:
      - platform: time
        at: "22:00:00"
    action:
      - service: mqtt.publish
        data:
          topic: "dashboard/display/command"
          payload: "off"
```

**Example 3: Turn display on in the morning**

```yaml
automation:
  - alias: "Dashboard Display On - Morning"
    trigger:
      - platform: time
        at: "07:00:00"
    condition:
      - condition: state
        entity_id: binary_sensor.workday
        state: "on"
    action:
      - service: mqtt.publish
        data:
          topic: "dashboard/display/command"
          payload: "on"
```

**Example 4: Create MQTT sensor for display status**

Add this to your `configuration.yaml` to track display status in Home Assistant:

```yaml
mqtt:
  sensor:
    - name: "Dashboard Display Status"
      state_topic: "dashboard/display/status"
      availability_topic: "dashboard/display/availability"
      payload_available: "online"
      payload_not_available: "offline"
      icon: mdi:monitor
```

#### Manual Display Control

You can also control the display directly on the Pi:

```bash
# Turn display on/off manually
python3 ~/dashboard-project/scripts/display_control.py on
python3 ~/dashboard-project/scripts/display_control.py off

# Check current power state
python3 ~/dashboard-project/scripts/display_control.py status
```


## Resources

- [Home Assistant Documentation](https://www.home-assistant.io/docs/)
- [Kids Chores Integration](https://github.com/ad-ha/kidschores-ha)
- [Kids Chores Dashboard](https://github.com/ccpk1/kidschores-ha-dashboard)
- [Raspberry Pi Documentation](https://www.raspberrypi.org/documentation/)
- [GPIO Zero Documentation](https://gpiozero.readthedocs.io/)

## Project Goals

1. **Primary:** Wall-mounted family chore management system
2. **Secondary:** Multi-function dashboard (calendar, smart home, weather)
3. **Aesthetic:** High WAF (Wife Acceptance Factor) - clean, modern interface
4. **Location:** Prominent area in home - needs to look good and be functional
5. **Maintenance:** Minimal physical access required after installation
