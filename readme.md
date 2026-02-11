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
- **jq** - JSON processor for configuration management

### Python Libraries
- `gpiozero` - GPIO sensor control
- `RPi.GPIO` - Low-level GPIO access
- `paho-mqtt` - MQTT client for Home Assistant integration

### Utilities
- `unclutter` - Hides mouse cursor when idle
- `xdotool` - Simulates keyboard/mouse input for automation
- `onboard` - On-screen keyboard for touchscreen input
- `wlopm` - Wayland display power management
- `vim`, `curl`, `htop` - Standard utilities

## Home Assistant Integration

### Infrastructure
- **Home Assistant VM** running on Ubuntu Desktop (basement server, not dashboard)
- **MQTT Broker** running on Home Assistant server for device communication

### Integrations
- **MQTT Display Control** - Turn dashboard display on/off via Home Assistant automations
- **MQTT Auto-Discovery** - The Pi automatically registers itself as a "Dashboard Pi" device in Home Assistant. No manual `configuration.yaml` editing needed -- the display switch entity appears automatically under Settings > Devices.

## Project Structure

```
dashboard-project/
├── config.json.template        # Configuration schema reference
├── config.json                 # Active config (git-ignored, created by bootstrap)
├── lib/
│   ├── config.sh               # Bash config loader (cfg_get, cfg_require)
│   └── config.py               # Python config loader (get, require)
├── kiosk/
│   └── kiosk.sh                # Chromium kiosk launcher
├── display/
│   └── display_control.py      # HDMI display power control (wlopm)
├── mqtt/
│   ├── mqtt_listener.py        # MQTT subscriber for HA integration
│   └── ha_init.py              # MQTT auto-discovery for Home Assistant
├── touchscreen/
│   └── touchscreen-check.sh    # Boot-time touchscreen detection
├── setup/
│   ├── bootstrap.sh            # Automated provisioning
│   ├── verify.sh               # Post-setup verification
│   ├── config-backup.sh        # Export config to backup
│   ├── config-restore.sh       # Restore config from backup
│   └── switch-branch.sh        # Switch branch + restart services
├── scripts/
│   ├── diagnose-usb.sh         # (legacy diagnostic)
│   └── usb-rescan.sh           # (legacy diagnostic)
└── readme.md                   # This file
```

## Installation & Setup

### Automated Bootstrap (Recommended)

Run the bootstrap script after cloning to a fresh Pi:

```bash
./setup/bootstrap.sh
```

Bootstrap will:
- Install required apt packages (jq, chromium, unclutter, etc.)
- Install paho-mqtt Python library
- Prompt for configuration values (dashboard URL, MQTT credentials, etc.)
- Generate `config.json` with your values
- Create systemd service files and autostart entry
- Set script permissions

After the script completes, confirm everything is configured correctly:

```bash
./setup/verify.sh
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

5. **Run Bootstrap:**
   ```bash
   ./setup/bootstrap.sh
   ./setup/verify.sh
   ```

### Kiosk Mode

The `kiosk/kiosk.sh` launcher starts Chromium in fullscreen kiosk mode on boot. All configuration (dashboard URL, Chromium data directory, on-screen keyboard size) is read from `config.json`.

**Autostart** is configured automatically by `setup/bootstrap.sh` -- the kiosk launches on login.

**Make script executable:** (the bootstrap script runs this step)
```bash
chmod +x kiosk/kiosk.sh
```

## Configuration Management

All project configuration is stored in a single `config.json` file at the repo root. This file is git-ignored so credentials are never committed.

### What is Configurable

| Section | Values |
|---------|--------|
| `dashboard` | Home Assistant URL |
| `mqtt` | Broker address, port, username, password, client ID, topics, heartbeat interval |
| `display` | Wayland display name |
| `touchscreen` | USB device ID, detection wait time |
| `kiosk` | Desktop load wait, on-screen keyboard size, Chromium data directory |
| `wifi` | SSID, password (for future watchdog) |
| `home_assistant` | Auth method |
| `browser` | Inactivity timeout, scheduled reboot interval |
| `system` | Reboot flag file path, log tag |

See `config.json.template` for the full schema with placeholder tokens.

### Backup Configuration

Export your configuration to a safe location:

```bash
./setup/config-backup.sh /path/to/backup.json
```

Without arguments, the backup is saved to `~/dashboard-config-backup.json`.

**Important:** The backup contains MQTT credentials. Store it securely.

### Restore Configuration

Restore a previously backed-up configuration:

```bash
./setup/config-restore.sh /path/to/backup.json
```

The restore script validates the backup file (valid JSON, required keys present) before applying it, then restarts services automatically.

## Usage

### Starting/Stopping Kiosk Mode

**Automatic Start:**
- Kiosk mode launches automatically on boot via autostart

**Manual Start:**
```bash
./kiosk/kiosk.sh
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

The dashboard integrates with Home Assistant via MQTT for remote display power management. The display entity is auto-discovered by Home Assistant -- no manual configuration.yaml editing is needed.

On first connection, the MQTT listener publishes a discovery payload to Home Assistant. This creates a "Dashboard Pi" device with a display power switch entity that you can use in automations and the HA dashboard.

#### MQTT Topics

The `mqtt-listener.service` subscribes and publishes to these topics (configurable in `config.json`):

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

With auto-discovery, the display switch entity is available as `switch.dashboard_display`. You can use it directly in automations:

**Example 1: Turn display on when motion detected**

```yaml
automation:
  - alias: "Dashboard Display On - Motion Detected"
    trigger:
      - platform: state
        entity_id: binary_sensor.living_room_motion
        to: "on"
    action:
      - service: switch.turn_on
        target:
          entity_id: switch.dashboard_display
```

**Example 2: Turn display off at bedtime**

```yaml
automation:
  - alias: "Dashboard Display Off - Bedtime"
    trigger:
      - platform: time
        at: "22:00:00"
    action:
      - service: switch.turn_off
        target:
          entity_id: switch.dashboard_display
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
      - service: switch.turn_on
        target:
          entity_id: switch.dashboard_display
```

#### Manual Display Control

You can also control the display directly on the Pi:

```bash
# Turn display on/off manually
python3 ~/dashboard-project/display/display_control.py on
python3 ~/dashboard-project/display/display_control.py off

# Check current power state (queries actual hardware via wlopm)
python3 ~/dashboard-project/display/display_control.py status
```

## Development Workflow

### Switching Between Dev and Production

The project uses branches for development. `main` is production, feature branches are for development.

Switch branches with one command:

```bash
./setup/switch-branch.sh <branch-name>
```

This will:
1. Check for uncommitted changes (aborts if any found)
2. Verify the target branch exists
3. Switch to the target branch
4. Regenerate systemd service files for the new branch paths
5. Restart services
6. Run verify.sh to confirm everything works

**Examples:**
```bash
./setup/switch-branch.sh main           # Switch to production
./setup/switch-branch.sh phase-2-dev    # Switch to development branch
```

**Note:** `config.json` is git-ignored, so it persists across branch switches. If switching to a branch that has never been bootstrapped on this Pi, run `./setup/bootstrap.sh` after switching.

## Recovery

### Fast Recovery from SD Card Failure

If your SD card fails or you need to set up a fresh Pi:

1. **Flash a fresh Raspberry Pi OS** using Raspberry Pi Imager (64-bit Desktop, configure SSH/WiFi/hostname)
2. **Clone the repo:**
   ```bash
   cd ~
   git clone <your-repo-url> dashboard-project
   cd dashboard-project
   ```
3. **Run bootstrap:**
   ```bash
   ./setup/bootstrap.sh
   ```
4. **Restore your config backup** (if you have one):
   ```bash
   ./setup/config-restore.sh /path/to/backup.json
   ```
5. **Reboot:**
   ```bash
   sudo reboot
   ```

**Config backup is essential for fast recovery.** Without a backup, you will need to re-enter all configuration values (MQTT credentials, dashboard URL, WiFi password, etc.) during the bootstrap prompts. With a backup, steps 3-5 take under a minute.

### Keeping a Config Backup

Back up your configuration after any changes:

```bash
./setup/config-backup.sh ~/dashboard-config-backup.json
```

Store the backup file somewhere off the Pi (USB drive, cloud storage, another machine). The file contains MQTT credentials, so keep it secure.

## Resources

- [Home Assistant Documentation](https://www.home-assistant.io/docs/)
- [Raspberry Pi Documentation](https://www.raspberrypi.org/documentation/)
- [GPIO Zero Documentation](https://gpiozero.readthedocs.io/)
- [paho-mqtt Documentation](https://eclipse.dev/paho/files/paho.mqtt.python/html/client.html)

## Project Goals

1. **Primary:** Wall-mounted family chore management system
2. **Secondary:** Multi-function dashboard (calendar, smart home, weather)
3. **Aesthetic:** High WAF (Wife Acceptance Factor) - clean, modern interface
4. **Location:** Prominent area in home - needs to look good and be functional
5. **Maintenance:** Minimal physical access required after installation
