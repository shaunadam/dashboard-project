# Technology Stack

**Analysis Date:** 2026-02-11

## Languages

**Primary:**
- Bash - Shell scripts for system automation and device control
- Python 3 - MQTT client, display control, and Home Assistant integration scripts

**Secondary:**
- Desktop Entry format - Autostart configuration files

## Runtime

**Environment:**
- Raspberry Pi OS with Desktop (64-bit)
- Raspberry Pi 4 (Model B)

**Package Manager:**
- apt (Debian/Ubuntu package manager)
- pip3 (Python package manager)

## Frameworks & Core Software

**Browser Runtime:**
- Chromium Browser - Kiosk mode display engine
  - Flags: `--kiosk`, `--disable-web-security`, `--user-data-dir=/tmp/chromium-kiosk`
  - Configuration: `scripts/kiosk.sh`

**GUI & Desktop:**
- GNOME Desktop - Default desktop environment
- Onboard - On-screen keyboard for touchscreen input
- Unclutter - Mouse cursor hiding when idle
- X11 - Display server for GUI rendering

**System Services:**
- systemd - Service management and auto-start configuration
- VNC - Remote desktop access

## Key Dependencies

**Critical:**
- Python 3 - Required for automation and MQTT integration
- Chromium Browser - Required for dashboard display in kiosk mode
- Git - Version control system
- Bash - Shell scripts for system automation

**Infrastructure:**
- paho-mqtt - MQTT client library for Home Assistant integration
  - Package: `paho-mqtt` (pip3)
  - Used in: `scripts/mqtt_listener.py`, `config/systemd/ha-init.py`
  - Purpose: Publish/subscribe to Home Assistant control topics

**GPIO & Hardware:**
- gpiozero - GPIO sensor control abstraction
  - Package: `python3-gpiozero` (apt)
  - Optional: Used for potential future GPIO sensor integration

- RPi.GPIO - Low-level GPIO access for Raspberry Pi
  - Package: `python3-rpi.gpio` (apt)
  - Optional: Fallback for GPIO operations

**Utilities:**
- curl - Network request utility for provisioning scripts
- htop - System monitoring
- vim - Text editor
- xdotool - X11 automation for keyboard/mouse simulation
  - Used in: `scripts/kiosk.sh`
  - Purpose: Simulate input for kiosk mode interactions

## APT Packages (System)

Automatically installed by `scripts/setup/bootstrap.sh`:

```
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
```

## Configuration Files

**Kiosk Launcher:**
- `scripts/kiosk.sh` - Chromium startup with environment setup
  - Exports: `DISPLAY=:0`
  - Sets: Screen blanking disabled, cursor hidden, on-screen keyboard enabled
  - Target URL: `http://192.168.68.75:8123` (Home Assistant instance)

**Autostart Configuration:**
- `config/autostart/kiosk.desktop` - GNOME autostart template
  - Uses token: `__REPO_ROOT__` (resolved by bootstrap.sh)
  - Deployed to: `~/.config/autostart/kiosk.desktop`
  - Format: Desktop Entry specification

**systemd Services:**
- `config/systemd/touchscreen-check.service` - Touchscreen auto-recovery
  - Type: `oneshot`
  - Triggers: `multi-user.target`
  - Script: `scripts/touchscreen-check.sh`

- `config/systemd/mqtt-listener.service` - MQTT display control daemon
  - Type: `simple`
  - Triggers: `network-online.target`
  - Script: `scripts/mqtt_listener.py`
  - User: `shaun`
  - Restart policy: Always restart (10s delay)

**MQTT Configuration:**
- `config/mqtt.json.template` - MQTT broker connection template
  - Template tokens: `__MQTT_BROKER__`, `__MQTT_USERNAME__`, `__MQTT_PASSWORD__`
  - Deployed to: `config/mqtt.json` (by bootstrap.sh)
  - Contains: broker IP/hostname, port, credentials
  - Permissions: `600` (readable only by user)

## Python Scripts

**MQTT Client:**
- `scripts/mqtt_listener.py` - MQTT subscriber daemon for display control
  - Library: `paho.mqtt.client`
  - Logging: Configured via Python logging module
  - Runs as: systemd service

**Display Control:**
- `scripts/display_control.py` - HDMI display power management
  - Method: Uses `wlopm` command via subprocess
  - Environment: Wayland display and XDG_RUNTIME_DIR setup
  - Commands: `on`, `off`, `status`

**Home Assistant Discovery:**
- `config/systemd/ha-init.py` - MQTT discovery publisher
  - Purpose: Auto-registers switch and button entities in Home Assistant
  - Library: `paho.mqtt.client`
  - Payload format: JSON (Home Assistant MQTT Discovery spec)

## Shell Scripts

**System Bootstrap:**
- `scripts/setup/bootstrap.sh` - Automated provisioning
  - Tasks: Package installation, service setup, template rendering
  - Template system: Token substitution (`__REPO_ROOT__`)

**Verification:**
- `scripts/setup/verify.sh` - Post-setup smoke testing
  - Checks: Commands, Python modules, service enablement, file permissions

**Touchscreen Management:**
- `scripts/touchscreen-check.sh` - USB touchscreen detection and recovery
  - Method: `lsusb` device detection
  - Device ID: `222a:0001` (ILITEK USB touchscreen)
  - Behavior: One automatic reboot if device missing on cold boot

**USB Management:**
- `scripts/diagnose-usb.sh` - USB device troubleshooting
- `scripts/usb-rescan.sh` - USB bus rescan utility

## Environment Variables

**Display:**
- `DISPLAY=:0` - X11 display server instance
- `XDG_RUNTIME_DIR=/run/user/{uid}` - Runtime directory for Wayland socket
- `WAYLAND_DISPLAY=wayland-0` - Wayland display socket

**GUI Toolkit:**
- `GDK_BACKEND=x11` - Forces GTK to use X11 instead of Wayland (for onboard keyboard)

## Boot Process

**Sequence:**
1. Raspberry Pi OS kernel and systemd initialization
2. `touchscreen-check.service` (oneshot) - Detects touchscreen at 60s, reboots if missing
3. Desktop environment loads (GNOME)
4. User auto-login triggers (configured via raspi-config)
5. `kiosk.desktop` autostart entry executes `scripts/kiosk.sh`
6. Chromium browser launches in fullscreen kiosk mode
7. `mqtt-listener.service` starts and connects to MQTT broker

## Development & Testing

**Verification Tool:**
- `scripts/setup/verify.sh` - Comprehensive system check
  - Validates: Commands, Python modules, service status, configuration files
  - Exit codes: 0 = all checks passed, 1 = issues detected

---

*Stack analysis: 2026-02-11*
