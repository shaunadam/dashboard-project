# Dashboard Kiosk

## What This Is

A Raspberry Pi 4-based kiosk that displays a Home Assistant family chore dashboard on a touchscreen. It boots to fullscreen, runs unattended, and integrates with Home Assistant via MQTT for remote display control. The system grew organically from debugging touchscreen issues to a functional home automation display — now it's time to harden, clean up, and professionalize.

## Core Value

The dashboard must boot from cold power-on to showing the week planner page with working touchscreen and zero human intervention.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Chromium kiosk mode launches on boot with zero intervention — existing
- ✓ Touchscreen detection with automatic soft reboot recovery (cold→soft boot pattern) — existing
- ✓ MQTT display control (on/off commands from Home Assistant) — existing
- ✓ Display power scheduling via HA automation (overnight screen off) — existing
- ✓ Bootstrap script for reproducible Pi setup — existing
- ✓ Post-setup verification script — existing
- ✓ On-screen keyboard available for touch input — existing
- ✓ MQTT-based HA discovery for display switch entity — existing
- ✓ Auto-login to Raspberry Pi OS on boot — existing (raspi-config)
- ✓ Auto-login to Home Assistant dashboard (likely via trusted networks + persistent session) — existing

### Active

<!-- Current scope. Building toward these. -->

- [ ] WiFi watchdog: auto-detect WiFi drops and reconnect using configured credentials
- [ ] Browser auto-recovery after WiFi reconnect (reload dashboard page)
- [ ] Touch-friendly scrolling: fix touch-drag to scroll instead of text selection
- [ ] Auto-return to week planner page after configurable inactivity timeout (default 10 min)
- [ ] Centralized configuration file for all magic numbers and hardcoded values
- [ ] Move dashboard URL from hardcoded in kiosk.sh to centralized config
- [ ] Move USB device ID from hardcoded in touchscreen-check.sh to centralized config
- [ ] Move inactivity timeout to centralized config
- [ ] WiFi credentials in centralized config (for watchdog)
- [ ] HA authentication method configurable
- [ ] Unit tests for MQTT listener (message parsing, command handling, reconnection)
- [ ] Unit tests for display control (command execution, error handling)
- [ ] Unit tests for bootstrap template rendering
- [ ] Fix display status reporting to Home Assistant (currently returns placeholder)
- [ ] Fix paho-mqtt dependency installation in bootstrap (currently commented out)
- [ ] Remove --disable-web-security flag (replace with proper approach)
- [ ] Chromium crash recovery (auto-restart if browser dies)
- [ ] Project cleanup: remove diagnostic scripts (diagnose-usb.sh, usb-rescan.sh)
- [ ] Project cleanup: remove KidChores references
- [ ] Improve project structure and organization (currently flat/organic)
- [ ] Improve HA integration/discovery setup
- [ ] Optimize touchscreen check startup delay (currently 60s on every boot)

### Out of Scope

<!-- Explicit boundaries. Includes reasoning to prevent re-adding. -->

- Fundamental changes to touchscreen cold→soft reboot pattern — took ages to get working, risk not worth it
- Multi-Pi dashboard support — single Pi deployment, no need for parameterized device identifiers
- Docker deployment on Pi — Pi 4 has limited resources, adds complexity without clear value for single-device setup
- Mobile app — web dashboard on Pi touchscreen is the product
- Real-time chat or complex HA integrations — kiosk is a display, not an input device
- Wayland migration — current X11 setup works, Wayland would break existing kiosk pattern

## Context

- **Hardware:** Raspberry Pi 4 Model B with ILITEK USB touchscreen (222a:0001)
- **Display server:** X11 with GNOME desktop
- **Home Assistant:** Runs on separate device at 192.168.68.75:8123 (reserved IP)
- **MQTT broker:** Configured in config/mqtt.json, used for display on/off control
- **Boot sequence:** Power on → systemd → touchscreen check (60s wait) → soft reboot if no touchscreen → desktop loads → auto-login → kiosk.sh → Chromium with HA dashboard
- **Pain points identified:** WiFi drops cause total lockout, touch-drag selects text instead of scrolling, family forgets to return to week planner, hardcoded values scattered across scripts
- **Development workflow:** Develop on Windows laptop, push to git, pull on Pi, test on hardware. Unit tests run locally. No local hardware simulation.
- **Organic growth:** Project started as debugging touchscreen issues, grew into functional kiosk. Code structure reflects this history — flat, pragmatic, but not organized for maintainability.
- **KidChores:** Previously used third-party integration, now replaced with custom HA integration. References may still exist in codebase. Remove them.

## Constraints

- **Hardware:** Raspberry Pi 4 — limited CPU/RAM, no containerization overhead
- **Touchscreen stability:** ILITEK USB touchscreen requires cold→soft reboot pattern; do NOT change this mechanism
- **Zero-intervention boot:** Cold boot must reach dashboard with working touchscreen without any human input
- **Network dependency:** HA dashboard requires network connectivity to Home Assistant on local network
- **Complexity budget:** Every change must earn its place. No complexity for complexity's sake. Prefer simple solutions.
- **Testing:** Hardware-dependent features (display, touchscreen, Wayland) can only be tested on Pi. Unit tests and config validation can run locally.
- **Security:** Auto-login is required (both OS and HA). Security measures must not interfere with unattended boot.

## Key Decisions

<!-- Decisions that constrain future work. Add throughout project lifecycle. -->

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Keep cold→soft reboot pattern for touchscreen | Took extensive debugging to find working solution; risk of breaking it outweighs any optimization | — Pending |
| Keep on-screen keyboard (onboard) | Useful for WiFi recovery without physical keyboard | — Pending |
| Develop on laptop, deploy via git pull | Simple workflow, no local hardware simulation needed for most work | — Pending |
| Unit tests run locally, hardware tests on Pi | Can't simulate touchscreen/display/Chromium locally | — Pending |
| Open to browser alternatives (e.g., FullyKiosk) | Current Chromium touch scrolling is broken; willing to experiment | — Pending |
| Centralized config over environment variables | Single config file easier to manage on single-Pi deployment | — Pending |

---
*Last updated: 2026-02-11 after initialization*
