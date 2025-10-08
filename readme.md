# Family Chore Dashboard

A wall-mounted touchscreen dashboard for family chore management, integrated with Home Assistant.

## Hardware

- **Raspberry Pi 4** (Model B)
- **15" USB Touchscreen Display**
- **MicroSD Card** (bootable system)
- **Future additions:**
  - Light sensor or ultrasonic sensor for automatic display on/off

## Software Stack

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
- **Home Assistant VM** running on Ubuntu Desktop (basement server)
- **IP Address:** `192.168.1.220`
- **Connection:** Ethernet (stable, reliable)

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

**Autostart Configuration:**
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

**Make script executable:**
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
ssh shaun@dashboard.local
pkill chromium
```

**Reboot:**
```bash
sudo reboot
```

### Remote Access

**SSH:**
```bash
ssh shaun@dashboard.local
```

**VNC:**
- Connect to `dashboard.local:5900` using VNC client

### Development Workflow

1. **Edit files locally** on your main machine
2. **Commit and push** to git repository
3. **SSH into Pi:**
   ```bash
   ssh shaun@dashboard.local
   cd ~/dashboard-project
   git pull
   ```
4. **Restart services** as needed:
   ```bash
   pkill chromium  # Kiosk will restart on next boot
   # or
   sudo reboot
   ```

## Future Enhancements

### Planned Features
- [ ] Light sensor integration for automatic display control
- [ ] Ultrasonic sensor for presence detection
- [ ] Dashboard aesthetic improvements
- [ ] Additional Home Assistant integrations (calendar, smart home controls)
- [ ] Watchdog service to restart browser if it crashes
- [ ] Automated backup script for configurations

### Sensor Integration
```python
# Example: Display control via light sensor
from gpiozero import LightSensor
import subprocess

sensor = LightSensor(17)  # GPIO pin 17
sensor.wait_for_light()
subprocess.run(['vcgencmd', 'display_power', '1'])  # Turn on
```

### Potential Improvements
- **USB SSD migration** for better longevity and performance
- **Static IP assignment** for reliability
- **Automated git pull** via cron for zero-touch updates
- **Custom CSS themes** for Home Assistant dashboard
- **Touch-optimized UI elements**

## Troubleshooting

### Kiosk Won't Start
```bash
# Check if script is executable
ls -l ~/dashboard-project/kiosk.sh

# Check autostart entry
cat ~/.config/autostart/kiosk.desktop

# Test script manually
DISPLAY=:0 ~/dashboard-project/kiosk.sh
```

### Display Issues
```bash
# Turn display on
vcgencmd display_power 1

# Turn display off
vcgencmd display_power 0

# Check display status
tvservice -s
```

### Network Issues
```bash
# Check IP address
hostname -I

# Check connectivity to Home Assistant
ping 192.168.1.220

# Check WiFi status
iwconfig
```

### Chromium Crashes
```bash
# Kill all chromium processes
pkill -9 chromium

# Clear chromium cache
rm -rf ~/.cache/chromium
rm -rf ~/.config/chromium

# Restart
sudo reboot
```

## Technical Notes

### Why Not Run Home Assistant on Pi?
- **Performance:** Pi 4 struggles with HA, especially database writes
- **SD Card Wear:** Constant writes reduce lifespan
- **Reliability:** VM on Ubuntu desktop is more stable
- **Updates:** Faster and more reliable on x86 architecture

### SD Card vs USB SSD
**Current:** Using SD card with git-based recovery strategy
- If card fails, re-image and `git pull`
- Good quality SD card should last 2-3+ years for this use case
- Much lighter write load than running Home Assistant

**Future:** Could migrate to USB SSD for better performance and longevity

### Environment Variables
- `DISPLAY=:0` - Tells GUI programs to use the Pi's physical display (required for SSH commands)

### Docker on Pi
- Docker runs well on Pi 4 (4GB+ models)
- Useful for future containerized services
- Portainer available for web-based management

## Maintenance

### Regular Updates
```bash
ssh shaun@dashboard.local
sudo apt update && sudo apt upgrade -y
sudo reboot
```

### Backup Configuration
```bash
# From Pi
cd ~/dashboard-project
git add .
git commit -m "Backup configuration"
git push

# Or backup to Home Assistant server
scp -r ~/dashboard-project/ user@192.168.1.220:/backup/path/
```

### Monitoring
```bash
# Check system resources
htop

# Check disk usage
df -h

# Check temperature
vcgencmd measure_temp
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

## License

Internal family use only.