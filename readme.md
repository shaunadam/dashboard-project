# Family Chore Dashboard

A wall-mounted touchscreen dashboard for family chore management, integrated with Home Assistant.

## Hardware

- **Raspberry Pi 4** (Model B)
- **15" USB Touchscreen Display**
- **MicroSD Card** (bootable system)

### Operating System
- **Raspberry Pi OS with Desktop** (64-bit)
- Hostname: `dashboard.local`
- Auto-login enabled for kiosk mode

### Core Software
- **Chromium Browser** - Kiosk mode display
- **Docker** - For containerized services (future use)
- **Python 3** - For automation scripts and sensor integration
- **Git** - Version control
- **VNC** - Remote desktop access

### Python Libraries
- `gpiozero` - GPIO sensor control
- `RPi.GPIO` - Low-level GPIO access

### Utilities
- `unclutter` - Hides mouse cursor when idle
- `xdotool` - Simulates keyboard/mouse input for automation
- `vim`, `curl`, `htop` - Standard utilities

## Home Assistant Integration

### Infrastructure
- **Home Assistant VM** running on Ubuntu Desktop (basement server, not dashboard)



### Integrations
- **Kids Chores Custom Integration** ([ad-ha/kidschores-ha](https://github.com/ad-ha/kidschores-ha))
- **Kids Chores Dashboard** ([ccpk1/kidschores-ha-dashboard](https://github.com/ccpk1/kidschores-ha-dashboard))

## Project Structure

```
~/dashboard-project/
├── kiosk.sh                 # Browser startup script
├── scripts/                 # Python automation scripts (future)
│   ├── display_control.py   # Sensor-based display control
│   └── ...
├── config/                  # Configuration files (future)
└── README.md               # This file
```

## Installation & Setup

### Automated Bootstrap (Recommended)

Run the bootstrap script after cloning to a fresh Pi:

```bash
./scripts/setup/bootstrap.sh
```

- Docker install is skipped by default; set `INSTALL_DOCKER=1` to enable it.
- Reboot once the script finishes so Docker group membership applies.
- Confirm everything with:

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
   
   # Install Docker
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker $USER
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

The `kiosk.sh` script launches Chromium in fullscreen kiosk mode on boot.

**kiosk.sh Configuration:**
```bash
#!/bin/bash

# Wait for desktop to load
sleep 10

# Hide mouse cursor
unclutter -idle 0.1 &

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
  --disable-features=TranslateUI \
  --no-first-run \
  --fast \
  --fast-start \
  --disable-default-apps \
  --display=:0 \
  http://192.168.1.220:8123/your-dashboard-path
```

**Autostart Configuration:** (handled automatically by `scripts/setup/bootstrap.sh`)
```bash
# Create autostart directory
mkdir -p ~/.config/autostart

# Create desktop entry
cat > ~/.config/autostart/kiosk.desktop << EOF
[Desktop Entry]
Type=Application
Name=Kiosk
Exec=/home/shaun/dashboard-project/kiosk.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
EOF
```

**Make script executable:** (the bootstrap script runs this step)
```bash
chmod +x kiosk.sh
```

## Usage

### Starting/Stopping Kiosk Mode

**Automatic Start:**
- Kiosk mode launches automatically on boot via autostart

**Manual Start:**
```bash
./kiosk.sh
```

**Exit Kiosk Mode (via SSH):**
```bash
ssh user@dashboard.local
pkill chromium


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
