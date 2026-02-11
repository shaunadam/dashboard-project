# Technology Stack

**Project:** Raspberry Pi Kiosk Dashboard Hardening
**Researched:** 2026-02-11
**Confidence:** MEDIUM-HIGH

## Recommended Stack

### Network Resilience

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| systemd-networkd | Built-in | Network configuration and WiFi management | Native to systemd, provides NetworkManager-free approach with better control over reconnection behavior. Use with `systemd-networkd-wait-online.service` to ensure network is up before critical services start. |
| NetworkManager dispatcher | Built-in | Event-driven network script execution | If using NetworkManager (default on Pi OS Desktop), dispatcher scripts in `/etc/NetworkManager/dispatcher.d/` provide reliable hooks for WiFi state changes without polling overhead. |
| Cron-based WiFi watchdog | N/A | Fallback connectivity monitoring | Simple bash script in cron (every 5 min) pings gateway, restarts wlan0 interface on failure. Battle-tested approach for kiosks. Lower overhead than full NetworkManager when paired with systemd-networkd. |
| systemd service watchdog | Built-in | Service-level health monitoring | Use `WatchdogSec=` and `Restart=on-watchdog` in service units for MQTT listener and browser. Systemd handles restart logic without external scripts. |

**Rationale:** Raspberry Pi OS Desktop uses NetworkManager by default, but for kiosks, systemd-networkd offers simpler, more deterministic reconnection. If sticking with NetworkManager, dispatcher scripts beat cron polling for responsiveness.

### Browser & Display

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Chromium | Latest from apt | Primary kiosk browser | Already in use, hardware-accelerated on Pi 4, excellent Home Assistant dashboard support. Fix touch issues with flags rather than switching browsers. |
| X11 (not Wayland) | Built-in | Display server | Raspberry Pi OS Bookworm defaults to Wayland, but kiosk mode is more stable on X11 in 2026. Switch via `raspi-config` for reliable fullscreen, cursor hiding, and autostart behavior. |
| unclutter | Latest from apt | Hide mouse cursor on X11 | Standard X11 solution. Does NOT work on Wayland (use wayfire plugins or GNOME extensions if forced to use Wayland). |
| systemd service with restart | Built-in | Browser crash recovery | Chromium service unit with `Restart=always`, `RestartSec=3s`, and `StartLimitBurst=5` prevents prolonged downtime from browser crashes. |

**Chromium Touch-Scroll Flags:**
```bash
--kiosk \
--touch-events=enabled \
--enable-features=OverlayScrollbar \
--disable-pinch \
--disable-features=OverscrollHistoryNavigation \
--overscroll-history-navigation=0 \
--disable-infobars \
--disable-session-crashed-bubble \
--no-first-run
```

**Why not alternatives:**
- **WPE WebKit:** Requires Buildroot/Yocto compilation (hours on Pi), minimal Home Assistant testing, fewer touch gesture controls.
- **FullyKiosk Browser:** Android-only (not available for Raspberry Pi OS).
- **Wayland:** Causes kiosk mode issues (no cursor hiding, panel appearing, autostart unreliable) as of Bookworm 2026.

### Testing Infrastructure

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| pytest | 9.0.2+ | Python unit/integration tests | Test `mqtt_listener.py`, `display_control.py`. Use fixtures to mock MQTT broker, GPIO, subprocess calls. Essential for CI/CD validation. |
| bats-core | 1.13.0+ | Bash script testing | Test `kiosk.sh`, `touchscreen-check.sh`, `bootstrap.sh`. TAP-compliant output integrates with CI. Community-maintained fork (original archived). |
| ShellCheck | 0.11.0+ | Bash static analysis | Catch common bash pitfalls before runtime. Run in pre-commit hook or CI. Integrates with VSCode. Zero runtime dependencies. |
| pytest-mock | Latest | Mocking framework for pytest | Mock `subprocess.run()` calls in display_control tests, mock MQTT client in listener tests. |
| systemd-watchdog (Python) | Latest | Systemd watchdog integration for Python | For MQTT listener to report health to systemd via `sd_notify(3)`. Enables `WatchdogSec=` in service unit. |

**Test Strategy:**
- **Unit tests (pytest):** Mock external dependencies (MQTT broker, systemd, hardware).
- **Integration tests (pytest + actual MQTT):** Use local Mosquitto instance in CI.
- **Script tests (bats):** Verify shell script logic, flag parsing, error handling.
- **Static analysis (ShellCheck):** Run on all `.sh` files before commit.

### Configuration Management

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Ansible | Latest | Automated provisioning and updates | Industry standard for Pi fleet management. Idempotent playbooks ensure consistency. Ansible's `lineinfile` module perfect for `/boot/config.txt` edits. Pull mode (run locally on Pi) or push mode (from control node) both viable. |
| Template-based config | N/A | Local configuration rendering | Current approach (`__REPO_ROOT__`, `__MQTT_*__` tokens) works well for single-device kiosks. Ansible Jinja2 templates are natural evolution for multi-device deployments. |

**Alternatives Considered:**
- **Salt Stack:** Less Pi community adoption than Ansible. Steeper learning curve.
- **Manual scripts:** Current `bootstrap.sh` approach is fine for single device, but doesn't scale to multiple kiosks or config drift detection.

**When to use each:**
- **Stick with bootstrap.sh:** Single kiosk, infrequent updates.
- **Migrate to Ansible:** Multiple kiosks, regular config updates, need for drift detection and rollback.

### MQTT & Display Control

| Library | Version | Purpose | Notes |
|---------|---------|---------|-------|
| paho-mqtt | 2.1.0+ | MQTT client for Python | Official Eclipse IoT library. Use VERSION2 callback API (VERSION1 deprecated, removed in 3.0). MQTT v5.0 support. Well-tested with Home Assistant. |
| RPi.GPIO | Latest | GPIO control for display | Current library for `display_control.py`. Works reliably on Pi 4. Alternatives like `gpiozero` offer higher abstraction but unnecessary for simple on/off control. |

**Configuration:**
- Use `config/mqtt.json` approach (already implemented).
- Never commit credentials to git.
- Ansible can template `mqtt.json` from vault for multi-device deployments.

## Installation

### Core System Packages
```bash
# Switch to X11 (required for stable kiosk mode)
sudo raspi-config nonint do_wayland W1  # W1 = X11, W2 = Wayland

# Install browser and utilities
sudo apt update
sudo apt install -y chromium-browser unclutter

# Install testing tools
sudo apt install -y shellcheck

# Install MQTT and GPIO libraries (Python)
pip3 install paho-mqtt==2.1.0 RPi.GPIO
```

### Testing Framework Setup
```bash
# Install Python testing tools
pip3 install pytest pytest-mock systemd-watchdog

# Install bats-core (from GitHub, not old apt version)
git clone https://github.com/bats-core/bats-core.git /tmp/bats-core
cd /tmp/bats-core
sudo ./install.sh /usr/local
```

### Optional: Ansible for Configuration Management
```bash
# On control machine (laptop/server)
pip3 install ansible

# On Raspberry Pi (for pull mode)
sudo apt install -y ansible
```

## Alternatives Considered

| Category | Recommended | Alternative | When to Use Alternative |
|----------|-------------|-------------|-------------------------|
| Display Server | X11 | Wayland | If Pi OS release fixes kiosk mode issues (check forums first). Wayland offers better security and performance in theory. |
| Browser | Chromium + flags | WPE WebKit | If Chromium memory footprint becomes issue on Pi Zero. Requires custom Buildroot image. |
| WiFi Watchdog | Cron script | NetworkManager dispatcher | If already using NetworkManager and want event-driven (not polling) approach. |
| Config Mgmt | Bootstrap script | Ansible | When managing 3+ kiosks or need config drift detection. |
| Testing | pytest + bats | Manual testing | Never. Automated tests catch regressions. |
| Python MQTT | paho-mqtt 2.1.0 | paho-mqtt 1.x | If stuck on Python <3.7 (unlikely on current Pi OS). Version 2.x required for MQTT v5.0. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Wayland (Pi OS Bookworm default) | Kiosk mode unreliable in 2026: cursor hiding broken, panel appears, autostart issues. Community reports widespread problems. | X11 via `raspi-config`. Battle-tested for kiosks. |
| paho-mqtt VERSION1 API | Deprecated, removed in paho-mqtt 3.0. No MQTT v5.0 support. | paho-mqtt 2.1.0+ with VERSION2 callback API. |
| ifplugd / netplug | Designed for cable detection (Ethernet plug/unplug). Not relevant for WiFi kiosk use case. Old, less maintained. | NetworkManager dispatcher or systemd-networkd for WiFi. |
| Old bats (sstephenson/bats) | Original repo archived in 2021. No updates. | bats-core (community-maintained fork). |
| Hardware watchdog (pywatchdog) | Interacts with kernel watchdog driver (`/dev/watchdog`). Overkill for kiosk. System-wide reboot on hang. | systemd service-level watchdog. Restarts just the failed service, not entire Pi. |
| Chromium installed via snap | Snap packaging causes permission issues, slower startup, larger footprint. | Native apt package: `chromium-browser`. |

## Stack Patterns by Use Case

### Single Kiosk (Current Project)
- Bootstrap script for provisioning
- Cron-based WiFi watchdog (simple, no NetworkManager complexity)
- X11 + Chromium with touch flags
- systemd service units with restart on failure
- pytest + bats for testing
- ShellCheck in development workflow

### Multi-Kiosk Fleet (Future)
- Ansible playbooks for provisioning
- systemd-networkd for network (simpler than NetworkManager at scale)
- Same browser/display stack
- Centralized pytest/bats in CI pipeline
- Ansible vault for MQTT credentials
- Monitoring via Home Assistant + MQTT status topics

### Low-Power Variant (Pi Zero W)
- Consider WPE WebKit (lower memory than Chromium)
- Buildroot custom image (removes desktop environment overhead)
- Same testing and watchdog patterns
- Expect slower performance, plan simpler dashboard

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| paho-mqtt 2.1.0 | Python 3.7+ | Requires VERSION2 callback API for MQTT v5.0. |
| pytest 9.0.2 | Python 3.10+ | Earlier versions work but miss newer features. |
| bats-core 1.13.0 | Bash 3.2+ | Portable across POSIX shells. |
| Chromium (apt) | Raspberry Pi OS Bookworm | Use apt version, not snap. |
| systemd-networkd | systemd 219+ | Built-in to all recent Pi OS versions. |
| X11 | Raspberry Pi OS (all) | Switch from Wayland via raspi-config. |

## Confidence Assessment

| Component | Level | Rationale |
|-----------|-------|-----------|
| Chromium flags | HIGH | Verified in official Chromium docs and multiple community kiosk guides (2024-2026). |
| X11 vs Wayland | HIGH | Extensive Pi forum evidence (2025-2026) shows Wayland kiosk issues. X11 recommended by community. |
| WiFi watchdog patterns | MEDIUM-HIGH | Multiple proven implementations in Pi community. Cron vs dispatcher choice is context-dependent. |
| Testing tools (pytest, bats) | HIGH | Official versions confirmed via PyPI and GitHub. Wide embedded Linux adoption. |
| WPE WebKit | MEDIUM | Requires Buildroot expertise. Less Home Assistant testing. Community projects exist but niche. |
| Ansible for Pi | MEDIUM-HIGH | Strong community adoption (GitHub examples), but best practices vary by use case (single vs fleet). |
| paho-mqtt version | HIGH | Confirmed via PyPI. VERSION2 API is documented standard for MQTT v5.0. |

## Sources

### High Confidence (Official Documentation & Current Releases)
- [pytest 9.0.2 - PyPI](https://pypi.org/project/pytest/) - Latest stable release, features
- [bats-core 1.13.0 - GitHub](https://github.com/bats-core/bats-core) - Latest release, TAP compliance
- [ShellCheck 0.11.0 - GitHub](https://github.com/koalaman/shellcheck/releases) - Latest release
- [paho-mqtt 2.1.0 - PyPI](https://pypi.org/project/paho-mqtt/) - Version, callback API migration
- [systemd.service - freedesktop.org](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) - Watchdog configuration
- [NetworkManager-dispatcher - freedesktop.org](https://networkmanager.dev/docs/api/latest/NetworkManager-dispatcher.html) - Event-driven scripts
- [WPE WebKit - Official](https://webkit.org/wpe/) - Embedded browser capabilities

### Medium Confidence (Community + Official Sources)
- [Chromium Kiosk Mode Guide - Smartupworld](https://smartupworld.com/chromium-kiosk-mode/) - Touch flags, best practices
- [Raspberry Pi Kiosk Setup - scalzotto.nl](https://www.scalzotto.nl/posts/raspberry-pi-kiosk/) - Chromium configuration
- [Pi OS Bookworm X11/Wayland Issues - Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=380416) - 2025-2026 reports
- [Ansible for Raspberry Pi - GitHub examples](https://github.com/geerlingguy/ansible-role-raspberry-pi) - Community patterns
- [Bash Testing Frameworks - GitHub comparison](https://github.com/dodie/testing-in-bash) - bats vs shunit2
- [pytest on Raspberry Pi - woteq.com](https://woteq.com/how-to-test-python-applications-running-on-raspberry-pi-with-pytest/) - Embedded testing

### Medium-Low Confidence (Community Forums, Needs Validation)
- [WiFi Watchdog Scripts - Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=313921) - Multiple cron approaches
- [Unclutter on Wayland - bist.be](https://bist.be/posts/unclutterwayland/) - Workarounds, alternatives
- [Building WPE for Pi 3 - Medium](https://samdecrock.medium.com/building-wpe-webkit-for-raspberry-pi-3-cdbd7b5cb362) - Build complexity

---
*Stack research for: Raspberry Pi Kiosk Dashboard Hardening*
*Researched: 2026-02-11*
*Overall confidence: MEDIUM-HIGH (verified core components, community patterns confirmed but context-dependent)*
