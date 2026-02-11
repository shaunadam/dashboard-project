# Feature Research

**Domain:** Raspberry Pi Kiosk Hardening (Production-Ready Family Dashboard)
**Researched:** 2026-02-11
**Confidence:** MEDIUM

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing these = product feels incomplete/unreliable.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Network Resilience - WiFi Watchdog** | Kiosks run 24/7, network failures inevitable | MEDIUM | Hardware watchdog with network ping monitoring. Standard for production Pi deployments. |
| **Browser Crash Recovery** | Chromium can crash, especially on resource-constrained Pi | LOW | Systemd service with `Restart=always`. Modern 2026 standard uses systemd over older autostart methods. |
| **Automatic Service Restart on Failure** | Systemd services (MQTT listener, etc.) must recover automatically | LOW | `Restart=on-failure` with restart limits. Table stakes for daemon processes. |
| **Screen Blanking Prevention** | User expects display to stay on 24/7 | LOW | Already implemented via `xset` commands. Verify it persists across reboots. |
| **Clean Shutdown Handling** | Prevents "Restore pages?" dialog on crashes | LOW | Already implemented via `--disable-session-crashed-bubble` and preferences file manipulation. |
| **Touch Scrolling Performance** | Touchscreen UX must feel responsive | MEDIUM | Requires hardware acceleration flags (`--disable-software-rasterizer`) and possibly touch scrolling extensions. |
| **On-Screen Keyboard** | Essential for touchscreen-only device | LOW | Already implemented with Onboard. Table stakes for any touchscreen kiosk. |
| **Kiosk Escape Prevention** | Prevent accidental exit via Alt+F4, Ctrl+W, etc. | LOW | `--kiosk` flag handles most cases. Consider desktop environment lockdown for production. |
| **Boot-to-Dashboard Reliability** | Must start automatically after power loss | LOW | Already implemented via autostart. Verify with power cycle testing. |
| **Basic System Monitoring** | CPU temp, disk space, service status visibility | MEDIUM | Without this, failures are silent until physical inspection. |

### Differentiators (Competitive Advantage)

Features that set the product apart. Not required, but valuable for family use case.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Auto-Return to Home Page** | After idle timeout, return to main dashboard | MEDIUM | Useful for multi-page dashboards. Requires idle detection + navigation script. |
| **Periodic Page Refresh** | Ensures HA dashboard stays current | LOW | Prevent stale data from caching. Use xdotool cron job or browser extension. |
| **Centralized Configuration** | Single config file for all settings (URLs, timeouts, MQTT) | MEDIUM | Reduces error-prone editing of multiple files. Improves maintainability. |
| **Touchscreen Calibration Verification** | Automated check that touch input matches display | MEDIUM | Detects misconfigured rotation/scaling. Prevents "touch is offset" issues. |
| **Health Check Dashboard** | Local web UI showing system status, logs, service health | HIGH | Family-friendly alternative to SSH + journalctl. Improves troubleshooting. |
| **Configuration Backup/Restore** | One-command backup of entire kiosk config to USB/NAS | MEDIUM | Speeds up recovery from SD card corruption or hardware replacement. |
| **Scheduled Display On/Off** | Time-based display control independent of HA | LOW | Fallback if MQTT fails. Extends display lifespan. |
| **Virtual Keyboard Auto-Hide** | Keyboard only appears when text input focused | LOW | Onboard has this built-in. Verify it's configured correctly. |
| **Browser Session Persistence** | Preserve HA login across browser restarts | LOW | Prevents re-login after Chromium crashes. Use persistent user-data-dir (not /tmp). |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems for single-Pi family setup.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Read-Only Filesystem** | Prevent SD card corruption from power loss | Breaking change; blocks logs, configs, caching. Complex to reverse for updates. | Hardware watchdog + scheduled backups. For 24/7 family kiosk, proper shutdown automation via HA is better. |
| **Remote Management Dashboard (24/7)** | Monitor kiosk from anywhere | Exposes attack surface, requires port forwarding or VPN. Overkill for single device in home. | SSH on local network + HA integration for status. Use Uptime Kuma on HA server if needed. |
| **Multi-User Login System** | Different family members have different views | Adds authentication complexity. Family dashboard should be shared/public. | Single kiosk mode. Use HA's person detection or time-based automations for context-aware displays. |
| **OTA Firmware Updates** | Auto-update Pi OS and packages | Risk of bricking kiosk during updates. SD card image replacement is safer for home use. | Manual update schedule during low-usage times. Test updates on dev Pi first. |
| **Custom Display Driver** | Optimize touchscreen performance | Maintenance burden. Kernel updates can break custom drivers. | Use mainline kernel drivers. Upgrade to officially supported touchscreen if needed. |
| **Offline-First Architecture** | Kiosk works without network | Contradicts HA dashboard purpose (needs network to display anything). Adds complexity. | Accept network dependency. Focus on network resilience (watchdog) instead. |
| **CI/CD Automated Deployment** | Deploy config changes automatically | Overkill for single Pi. Adds infrastructure (build server, runners). | Git pull + manual verification. Bootstrap script for fresh installs. |

## Feature Dependencies

```
[Network Resilience - WiFi Watchdog]
    └──requires──> [Hardware Watchdog Enabled]
                       └──requires──> [Kernel Watchdog Module Loaded]

[Browser Crash Recovery]
    └──requires──> [Systemd Service for Chromium]

[Auto-Return to Home Page]
    └──requires──> [Idle Detection Mechanism]
    └──requires──> [JavaScript Injection or xdotool]

[Centralized Configuration]
    └──requires──> [Bootstrap Script Refactor]
    └──enhances──> [Configuration Backup/Restore]

[Health Check Dashboard]
    └──requires──> [System Monitoring]
    └──requires──> [Local Web Server (e.g., Flask)]

[Touchscreen Calibration Verification]
    └──requires──> [xinput Configuration Parsing]

[Configuration Backup/Restore]
    └──conflicts──> [Read-Only Filesystem]

[Periodic Page Refresh]
    └──conflicts──> [Browser Session Persistence]
        # Frequent F5 may clear login state unless using persistent storage
```

### Dependency Notes

- **Network Resilience requires Hardware Watchdog:** Software-only watchdog can't recover from kernel panics or complete freezes. Raspberry Pi has hardware watchdog built-in (`bcm2835_wdt` module), must be enabled in `/etc/systemd/system.conf`.

- **Centralized Configuration enhances Backup/Restore:** Single config file makes backup trivial (copy one JSON). Multiple config files scattered across the system require complex backup scripts.

- **Auto-Return requires Idle Detection:** Must detect user inactivity. Options: xprintidle for X11 idle time, or monitor Chromium's last input timestamp.

- **Periodic Page Refresh conflicts with Session Persistence:** Aggressive F5 refreshes can clear browser cache/cookies. Use persistent `--user-data-dir` (not `/tmp`) and gentle refresh intervals (5-15 min).

- **Health Check Dashboard requires Web Server:** Adds another service to monitor. Consider lightweight alternatives (systemd email alerts, HA integration) before building custom web UI.

## MVP Definition

### Launch With (Hardening Milestone v1)

Minimum viable hardening — what's needed to make the kiosk production-ready for family use.

- [x] **Network Resilience - WiFi Watchdog** — Prevents silent failures when WiFi drops. Family shouldn't notice network blips.
- [x] **Browser Crash Recovery (Systemd)** — Chromium crashes are invisible to users. Dashboard auto-recovers.
- [x] **Automatic Service Restart on Failure** — MQTT listener, touchscreen-check must survive failures. No manual SSH intervention.
- [x] **Touch Scrolling Performance** — Dashboard must feel responsive. Poor scrolling = poor WAF (Wife Acceptance Factor).
- [x] **Centralized Configuration** — Single source of truth for URLs, MQTT, timeouts. Reduces deployment errors.
- [x] **Configuration Backup Script** — Fast recovery from SD card corruption. Copy config + re-run bootstrap.

### Add After Validation (Hardening v1.x)

Features to add once core hardening is proven stable.

- [ ] **Auto-Return to Home Page** — Add after confirming idle timeout needs (observe family usage patterns first). Trigger: "Users navigate away and forget to return."
- [ ] **Periodic Page Refresh** — Add if HA dashboard shows stale data. Trigger: "Data doesn't update without manual refresh."
- [ ] **Basic System Monitoring** — Add after v1 deployed. Trigger: "Need visibility into failures without SSH."
- [ ] **Scheduled Display On/Off** — Add if MQTT display control proves unreliable. Trigger: "Display doesn't turn off at bedtime."
- [ ] **Browser Session Persistence** — Add if re-login becomes annoying. Trigger: "HA login expires too frequently."

### Future Consideration (v2+)

Features to defer until production usage reveals needs.

- [ ] **Health Check Dashboard** — Defer until SSH troubleshooting becomes frequent. High effort, uncertain ROI.
- [ ] **Touchscreen Calibration Verification** — Add only if touch offset issues appear. Trigger: "Touch input doesn't match visual target."
- [ ] **Virtual Keyboard Auto-Hide** — Verify Onboard's built-in behavior first. Only customize if family complains.
- [ ] **Configuration Backup to NAS** — Defer until manual backup to USB proves insufficient. Trigger: "Need automated backups."

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Network Resilience - WiFi Watchdog | HIGH | MEDIUM | P1 |
| Browser Crash Recovery (Systemd) | HIGH | LOW | P1 |
| Automatic Service Restart on Failure | HIGH | LOW | P1 |
| Touch Scrolling Performance | HIGH | MEDIUM | P1 |
| Centralized Configuration | MEDIUM | MEDIUM | P1 |
| Configuration Backup Script | HIGH | LOW | P1 |
| Auto-Return to Home Page | MEDIUM | MEDIUM | P2 |
| Periodic Page Refresh | MEDIUM | LOW | P2 |
| Basic System Monitoring | MEDIUM | MEDIUM | P2 |
| Scheduled Display On/Off | LOW | LOW | P2 |
| Browser Session Persistence | MEDIUM | LOW | P2 |
| Health Check Dashboard | LOW | HIGH | P3 |
| Touchscreen Calibration Verification | LOW | MEDIUM | P3 |
| Configuration Backup to NAS | LOW | MEDIUM | P3 |
| Virtual Keyboard Auto-Hide | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for production readiness (blocking for family deployment)
- P2: Should have, add when v1 proves stable
- P3: Nice to have, defer until usage patterns reveal need

## Competitor Feature Analysis

*Note: "Competitors" here are reference implementations and production Pi kiosk projects.*

| Feature | geerlingguy/pi-kiosk | FullPageOS | Our Approach |
|---------|----------------------|------------|--------------|
| **Network Resilience** | Not included (assumes stable network) | Basic connectivity check | Hardware watchdog + network ping monitoring (more robust) |
| **Crash Recovery** | Systemd service with Restart=always | Built-in (auto-restart loop) | Systemd service (follows 2026 best practices) |
| **Configuration Management** | Ansible playbook (overkill for single Pi) | SD card image with hardcoded config | Single JSON config file + bootstrap script (balance simplicity/flexibility) |
| **Touch Scrolling** | Not addressed (desktop browser focus) | Mobile-optimized scrolling | Hardware acceleration flags + touch extensions |
| **Monitoring** | None (assumes SSH access) | None | Basic systemd monitoring + optional HA integration |
| **Lockdown** | Basic kiosk flags | Full lockdown (read-only FS, no SSH) | Moderate lockdown (preserves dev access for family use) |
| **Display Control** | No remote control | No remote control | MQTT integration with HA (unique to our setup) |

## Sources

### Official Documentation
- [Raspberry Pi - How to use a Raspberry Pi in kiosk mode](https://www.raspberrypi.com/tutorials/how-to-use-a-raspberry-pi-in-kiosk-mode/)
- [Chromium Blog - Smoothing out scrolling experience](https://blog.chromium.org/2023/08/smoothing-out-scrolling-experience-in.html)
- [Chrome for Developers - More compatible, smoother touch](https://developer.chrome.com/blog/a-more-compatible-smoother-touch?hl=en)

### Production Hardening References
- [Mender - Raspberry Pi in Production Considerations](https://mender.io/blog/raspberry-pi-in-production)
- [Raspberry Pi Security Hardening Guide](https://ohyaan.github.io/tips/raspberry_pi_security_hardening_complete_guide/)
- [Peridio - Production-Ready Raspberry Pi Deployment](https://docs.peridio.com/solutions/raspberry-pi/raspberry-pi)

### Network Resilience
- [Dries Buytaert - Keeping Raspberry Pi Online with Watchdogs](https://dri.es/keeping-your-raspberry-pi-online-with-watchdogs)
- [Diode - Running Forever with Raspberry Pi Hardware Watchdog](https://diode.io/blog/running-forever-with-the-raspberry-pi-hardware-watchdog)
- [Xavier.Arnaus.net - Watchdog Service for Raspberry Pi](https://xavier.arnaus.net/blog/watchdog-service-for-raspberry-pi-machines)

### Browser & Display Features
- [Luke Browning - Touch Screen Chromium Kiosk on Raspberry Pi](https://lukebrowning.com/hardware/raspberry-pi/touch-screen-chromium-kiosk-on-the-raspberry-pi/)
- [Copyprogramming - Raspberry Pi Chromium Kiosk 2026 Best Practices](https://copyprogramming.com/howto/raspberry-pi-4-autostart-chromium)
- [GitHub - MatteoGauthier - Chromium kiosk touchable experience](https://gist.github.com/MatteoGauthier/30df80fc65e0ffee36d18652129b7c24)

### System Monitoring
- [Sunfounder - Raspberry Pi System Monitor with Monit](https://www.sunfounder.com/blogs/news/raspberry-pi-system-monitor-guide-how-to-track-cpu-ram-temperature-and-services-with-monit)
- [PiCockpit - PiDoctor System Health Monitor](https://picockpit.com/raspberry-pi/pidoctor-raspberry-pi-system-health-monitor/)

### Systemd Service Management
- [Chris Dzombak - Keep Software Running on Raspberry Pi](https://www.dzombak.com/blog/2023/12/keep-your-software-up-and-running-on-the-raspberry-pi/)
- [TheLinuxCode - Checking Service Status on Raspberry Pi](https://thelinuxcode.com/check-status-of-service-in-raspberry-pi/)

### Configuration & Security
- [Configure Raspberry Pi as Kiosk Display](https://reelyactive.github.io/diy/pi-kiosk/)
- [Honlsoft - Setting up Raspberry Pi Kiosk](https://www.honlsoft.com/blog/2020-03-06-pi-plate-setting-up-kiosk/)

### Home Assistant Integration
- [GitHub - leukipp/touchkio](https://github.com/leukipp/touchkio)
- [GitHub - NemesisRE/kiosk-mode](https://github.com/NemesisRE/kiosk-mode)
- [Pi My Life Up - Raspberry Pi Home Assistant Kiosk](https://pimylifeup.com/raspberry-pi-home-assistant-kiosk/)
- [SmartHomeJunkie - Kiosk Mode in Home Assistant](https://www.smarthomejunkie.net/kiosk-mode-in-home-assistant-the-right-way/)

### SD Card Protection
- [Core Electronics - Read-Only Raspberry Pi](https://core-electronics.com.au/guides/read-only-raspberry-pi/)
- [Medium - Make Raspberry Pi File System Read-Only](https://medium.com/swlh/make-your-raspberry-pi-file-system-read-only-raspbian-buster-c558694de79)
- [Adafruit - Read-Only Raspberry Pi](https://learn.adafruit.com/read-only-raspberry-pi/overview)

### CI/CD & Testing (Research Only - Marked as Anti-Feature)
- [Jakob Breu - Simple CI/CD for Embedded Devices](https://jakobbr.eu/2022/04/23/simple-ci-cd-for-embedded-devices/)
- [BeetleboxCI - Getting Started with Raspberry Pi](https://docs.beetleboxci.com/docs/tutorials/getting-started-raspberry-pi-overview)

---
*Feature research for: Raspberry Pi Kiosk Hardening*
*Researched: 2026-02-11*
