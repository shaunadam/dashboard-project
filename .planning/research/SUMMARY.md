# Project Research Summary

**Project:** Raspberry Pi Kiosk Dashboard Hardening
**Domain:** Embedded Kiosk Systems (Production-Ready Home Automation Display)
**Researched:** 2026-02-11
**Confidence:** MEDIUM-HIGH

## Executive Summary

This project transforms a functional Raspberry Pi kiosk running a Home Assistant dashboard into a production-hardened, 24/7-reliable family device. Research reveals that the current implementation has working basics (browser launch, MQTT control, touchscreen recovery) but lacks critical resilience patterns that production kiosks require. The primary challenges are network resilience (WiFi watchdogs that avoid boot loops), browser crash recovery (supervised restart without manual intervention), display control reliability (vcgencmd is broken by modern kernel drivers), and MQTT connection stability (threading deadlocks after 12-24 hours).

The recommended approach prioritizes fixing broken core functionality first (display control using wlopm instead of vcgencmd, MQTT status verification), then layering automated recovery mechanisms (WiFi watchdog with boot-loop protection, browser process supervision), and finally implementing centralized configuration to prevent drift across multiple scripts. The architecture should follow systemd-native patterns with proper service dependencies, using X11 over Wayland for kiosk stability, and implementing staged network recovery rather than aggressive reboots.

Key risks include network watchdog creating infinite reboot loops (requires flag-file protection like existing touchscreen-check.sh), MQTT listener threading deadlocks after long uptime (requires external health checks and heartbeat publishing), and filesystem corruption from power loss (mitigated with tmpfs logging and overlay filesystem). The project should maintain its lightweight bootstrap-script approach for single-device deployment while building toward Ansible-based configuration management if multiple kiosks are deployed.

## Key Findings

### Recommended Stack

Modern Raspberry Pi kiosks require a balance between simplicity and resilience. The core finding is that **Raspberry Pi OS Bookworm defaults (Wayland, NetworkManager) are problematic for kiosks** — community evidence strongly favors X11 for stable fullscreen behavior and systemd-networkd for deterministic WiFi recovery. For display control, **vcgencmd is obsolete** with vc4-kms-v3d driver; wlopm (Wayland) or xset dpms (X11) are required replacements.

**Core technologies:**
- **X11 (not Wayland):** Kiosk mode is more stable — cursor hiding works, fullscreen reliable, autostart predictable
- **Chromium with touch flags:** Already in use; fix touch issues with flags (`--touch-events=enabled`, `--enable-features=OverlayScrollbar`) rather than switching browsers
- **systemd-networkd + WiFi watchdog:** Simpler than NetworkManager for kiosk use; cron-based ping watchdog is battle-tested pattern
- **paho-mqtt 2.1.0+ (VERSION2 API):** VERSION1 deprecated; use `loop_forever()` not `loop_start()` to avoid threading deadlocks
- **pytest + bats-core + ShellCheck:** Essential for preventing regressions — pytest for Python, bats for bash, ShellCheck for static analysis
- **wlopm or xset dpms:** Replace vcgencmd for display power control (vcgencmd broken with KMS driver)
- **systemd service watchdog:** Use `WatchdogSec=` and `Restart=on-failure` for automatic service recovery

**Critical version requirements:**
- paho-mqtt 2.1.0+ (VERSION1 API removed in 3.0)
- bats-core 1.13.0+ (original bats archived, use community fork)
- ShellCheck 0.11.0+ for bash linting

### Expected Features

Production kiosk hardening is about resilience, not features. Users expect the dashboard to "just work" 24/7 without manual intervention.

**Must have (table stakes):**
- **Network Resilience (WiFi Watchdog)** — Kiosks run continuously; network failures are inevitable; automatic recovery is assumed
- **Browser Crash Recovery** — Chromium crashes must be invisible to users; systemd Restart=always is modern standard
- **Automatic Service Restart** — All daemons (MQTT listener, watchdogs) must self-heal on failure
- **Touch Scrolling Performance** — Touchscreen UX must feel responsive; poor scrolling = poor Wife Acceptance Factor
- **Clean Shutdown Handling** — Prevent "Restore pages?" dialogs after crashes
- **Kiosk Escape Prevention** — Prevent accidental exit via keyboard shortcuts

**Should have (competitive):**
- **Centralized Configuration** — Single JSON config for all settings (URLs, MQTT, timeouts) reduces deployment errors
- **Configuration Backup/Restore** — Fast recovery from SD card corruption
- **Auto-Return to Home Page** — After idle timeout, return to main dashboard (useful for multi-page dashboards)
- **Periodic Page Refresh** — Prevent stale data from caching in browser
- **Browser Session Persistence** — Preserve HA login across browser restarts (use persistent user-data-dir)

**Defer (v2+):**
- **Health Check Dashboard** — Local web UI for troubleshooting (high effort, uncertain ROI until SSH proves insufficient)
- **Touchscreen Calibration Verification** — Only needed if touch offset issues appear
- **Read-Only Filesystem** — Breaking change; blocks logs and configs; proper shutdown automation is better for family use

### Architecture Approach

The standard architecture for production Pi kiosks follows a **layered supervision pattern**: user-facing browser layer, control layer (watchdogs), service orchestration (systemd), and integration layer (MQTT, display control). The critical insight is that **autostart without supervision is an anti-pattern** — browser must be launched by a supervisor daemon that monitors health and restarts on crash.

**Major components:**
1. **Browser Watchdog (Python daemon)** — Monitors Chromium process, restarts on crash, dismisses error dialogs; supervised by systemd with Restart=on-failure
2. **WiFi Watchdog (systemd timer + bash)** — Ping-based connectivity check every 5 minutes; staged recovery (restart NetworkManager → wait → reboot); flag-file protection prevents boot loops
3. **Centralized Config (JSON)** — Single source of truth loaded by all scripts; prevents hardcoded values scattered across codebase
4. **systemd Service Dependencies** — Use After=network-online.target (not network.target) + Wants= for soft dependencies; avoid Requires= for network (may recover)
5. **MQTT Listener with Heartbeat** — Use loop_forever() not loop_start(); publish heartbeat every 60-120s; external health check monitors message processing

**Key architectural decisions:**
- **Centralized config first** — All other components depend on it; build foundation before adding watchdogs
- **WiFi watchdog before browser watchdog** — Simpler implementation; browser needs network but watchdog logic is independent
- **Integration updates last** — MQTT listener and display control already work; just migrate to centralized config
- **Testing infrastructure final** — Tests depend on understanding implementation; mock hardware for unit tests, integration tests on real Pi

### Critical Pitfalls

Research identified 10 critical pitfalls, with 5 blocking production readiness:

1. **vcgencmd Display Control Broken by KMS Driver** — vcgencmd display_power fails silently with vc4-kms-v3d driver (default in Bullseye+); must use wlopm (Wayland) or xset dpms (X11); verify on actual hardware
2. **MQTT Reconnection Threading Deadlock** — paho-mqtt loop_start() causes deadlocks after 12-24 hours; listener appears active but stops processing messages; use loop_forever() + heartbeat publishing + external health check
3. **systemd Service Dependency Race Conditions** — After=network.target doesn't wait for actual connectivity (just network subsystem start); use After=network-online.target + Wants=network-online.target; test with cold boot (power cycle), not systemctl restart
4. **Network Watchdog Creates Infinite Reboot Loop** — Watchdog detects "network down" during boot, reboots before WiFi stabilizes, enters loop; requires flag-file protection (like touchscreen-check.sh pattern) + 90-120 second boot delay
5. **MQTT Status Reporting Lies to Home Assistant** — Current mqtt_listener publishes status immediately after command, doesn't verify actual display state; display_control.py status check not implemented; must query actual state before publishing

**Prevention strategies:**
- Remove --disable-web-security flag (critical security hole, never needed)
- Implement multi-stage network validation (gateway ping → DNS ping → DNS resolve → HTTP GET) before reboot
- Use Restart=on-failure with StartLimitBurst=5 to prevent boot loops
- Mock hardware in unit tests but require integration tests on real Pi
- Never hardcode paths; use __REPO_ROOT__ template tokens rendered by bootstrap

## Implications for Roadmap

Based on research, the hardening project should be structured into 4 phases following dependency order identified in architecture research.

### Phase 1: Core Functionality Fixes
**Rationale:** Fix broken functionality before adding new resilience features; these are blocking issues that make current features unreliable

**Delivers:**
- Display control that works with modern kernel drivers
- Accurate MQTT status reporting to Home Assistant
- Validated Chromium input handling (both touch and mouse)
- Security audit (remove --disable-web-security if present)

**Addresses:**
- Table stakes: Clean shutdown handling, kiosk escape prevention
- Pitfalls: vcgencmd broken by KMS, MQTT status lies, Chromium touch flags break mouse, --disable-web-security attack vector

**Components:**
- Update display_control.py to use wlopm/xset dpms instead of vcgencmd
- Implement status query in display_control.py
- Update mqtt_listener.py to query actual state before publishing
- Audit kiosk.sh Chromium flags, remove unnecessary input overrides
- Verify X11 configuration (switch from Wayland if needed)

**Research flag:** LOW — Standard patterns, well-documented solutions

### Phase 2: Resilience & Watchdogs
**Rationale:** Network and browser failures are inevitable; automated recovery is table-stakes for 24/7 operation; depends on Phase 1 working correctly

**Delivers:**
- WiFi watchdog with boot-loop protection
- Browser crash recovery via process supervision
- MQTT connection reliability improvements
- Automated service restart policies

**Addresses:**
- Table stakes: Network resilience, browser crash recovery, automatic service restart
- Pitfalls: MQTT threading deadlock, network watchdog reboot loop, systemd dependency races

**Components:**
- WiFi watchdog (systemd timer + bash script, flag-file protection, staged recovery)
- Browser watchdog (Python daemon supervising Chromium process)
- MQTT heartbeat publishing and external health check
- Update service dependencies (After=network-online.target)
- systemd service files with proper Restart policies

**Research flag:** MEDIUM — WiFi watchdog requires careful tuning to avoid boot loops; study community patterns for staged recovery

### Phase 3: Centralized Configuration & Management
**Rationale:** Prevents configuration drift, enables easier backup/restore; foundation for future multi-device deployment

**Delivers:**
- Single JSON config file consumed by all scripts
- Template-based configuration with bootstrap rendering
- Configuration backup/restore script
- Path validation in verify.sh

**Addresses:**
- Differentiators: Centralized configuration, configuration backup/restore
- Pitfalls: Hardcoded values scattered across scripts, path restructuring breaks services, secrets in git

**Components:**
- config/kiosk.json.template (replaces mqtt.json.template)
- scripts/lib/config.py (shared config loader)
- Update all scripts to load from centralized config
- Update bootstrap.sh to render kiosk.json from prompts
- Add verify.sh checks for path validation

**Research flag:** LOW — Standard configuration management patterns

### Phase 4: Testing & Polish
**Rationale:** Ensure changes don't introduce regressions; improve maintainability; validate hardware-dependent behavior

**Delivers:**
- Unit tests with mocked hardware
- Integration tests on actual Pi
- Static analysis (ShellCheck) in workflow
- Documentation of testing requirements

**Addresses:**
- Testing infrastructure (pytest, bats, ShellCheck)
- Pitfalls: Hardware mocking tests pass locally but fail on Pi, filesystem corruption from power loss

**Components:**
- tests/unit/ with mocked GPIO, subprocess, MQTT
- tests/integration/ requiring real Pi hardware
- ShellCheck integration for all .sh files
- Document which tests require hardware
- Optional: tmpfs for /var/log to prevent journal corruption

**Research flag:** LOW — Standard testing patterns, well-documented tools

### Phase Ordering Rationale

- **Phase 1 first** because broken display control and MQTT status are blocking issues that make existing features unreliable; must fix before adding complexity
- **Phase 2 second** because watchdogs depend on Phase 1 working correctly (e.g., WiFi watchdog needs working network service, browser watchdog needs known-good browser launch)
- **Phase 3 third** because centralized config is easier to implement once components are stable; refactoring config during watchdog development creates confusion
- **Phase 4 last** because tests depend on understanding implementation; can't test effectively until components are built

**Dependency chain:**
```
Phase 1 (Fixes) → Phase 2 (Watchdogs) → Phase 3 (Config) → Phase 4 (Testing)
    ↓                   ↓                     ↓
Working display    Network resilience   Single config    Regression
Working MQTT       Browser recovery     Easy backup      prevention
Secure flags       Service restarts     Path validation  Hardware tests
```

**How this avoids pitfalls:**
- Phase 1 addresses vcgencmd breakage, MQTT status lies, security issues
- Phase 2 implements boot-loop protection BEFORE deploying WiFi watchdog
- Phase 3 prevents path restructuring issues by using templates from start
- Phase 4 catches mock test false confidence by requiring hardware integration tests

### Research Flags

**Phases likely needing deeper research during planning:**
- **Phase 2 (Resilience & Watchdogs):** WiFi watchdog boot-loop protection requires studying community patterns; research flag-file patterns, staged recovery timing, ping target selection
- **Phase 3 (Config Management):** If scaling to multiple kiosks, research Ansible patterns and vault for secrets (currently out of scope for single device)

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Core Fixes):** wlopm/xset dpms are well-documented; standard systemd service patterns
- **Phase 4 (Testing):** pytest, bats, ShellCheck have extensive documentation and examples

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Chromium flags, X11 vs Wayland, paho-mqtt versions verified via official docs and multiple community sources (2024-2026) |
| Features | MEDIUM | Feature prioritization based on community kiosk projects; table stakes clear, but differentiators are context-dependent |
| Architecture | MEDIUM | Standard patterns identified across multiple sources; centralized config and watchdog supervision are proven, but implementation details vary |
| Pitfalls | HIGH | Extensive Pi forum evidence for vcgencmd breakage, MQTT threading issues, network watchdog loops; pitfalls are well-documented with multiple reports |

**Overall confidence:** MEDIUM-HIGH

The core technical recommendations (X11, wlopm, systemd patterns, paho-mqtt VERSION2) are verified with high confidence through official documentation and current community consensus. The architectural patterns (browser watchdog, WiFi watchdog, centralized config) are standard but require careful implementation — especially boot-loop protection which is critical.

### Gaps to Address

**During Phase 1 Planning:**
- Verify display_control.py currently uses vcgencmd (assumed based on common pattern, but code should be checked)
- Determine if Chromium flags include --disable-web-security (needs audit of kiosk.sh)
- Confirm whether system is using X11 or Wayland (check /boot/config.txt and raspi-config settings)

**During Phase 2 Planning:**
- Research optimal ping targets for WiFi watchdog (gateway vs. public DNS vs. both)
- Determine appropriate boot delay before first network check (90-120s recommended, needs validation)
- Study touchscreen-check.sh flag-file pattern for WiFi watchdog adaptation

**During Implementation:**
- Test wlopm vs. xset dpms on actual hardware (can't be validated on Windows dev machine)
- Validate MQTT threading behavior over 48+ hour uptime (requires long-running test)
- Confirm power-loss filesystem corruption risk (optional: implement overlay FS or tmpfs logging if family reports issues)

**Future Validation:**
- If deploying multiple kiosks, revisit Ansible vs. bootstrap script decision (current recommendation: stick with bootstrap for single device)
- If HA dashboard shows stale data, implement periodic page refresh (defer until observed)
- If touch offset issues appear, implement calibration verification (defer until triggered)

## Sources

### Primary (HIGH confidence)
- [Raspberry Pi Official — How to use a Raspberry Pi in kiosk mode](https://www.raspberrypi.com/tutorials/how-to-use-a-raspberry-pi-in-kiosk-mode/) — Kiosk setup patterns
- [Chromium Blog — Smoothing out scrolling experience](https://blog.chromium.org/2023/08/smoothing-out-scrolling-experience-in.html) — Touch scrolling flags
- [systemd.service — freedesktop.org](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) — Service dependencies, watchdog configuration
- [paho-mqtt 2.1.0 — PyPI](https://pypi.org/project/paho-mqtt/) — VERSION2 API migration, MQTT v5.0 support
- [pytest 9.0.2 — PyPI](https://pypi.org/project/pytest/) — Latest stable release
- [bats-core 1.13.0 — GitHub](https://github.com/bats-core/bats-core) — Community-maintained fork, TAP compliance

### Secondary (MEDIUM confidence)
- [Pi Forums — HDMI power on/off problems vcgencmd broken](https://forums.raspberrypi.com/viewtopic.php?t=347425) — Multiple reports of vcgencmd breakage with KMS driver
- [Pi Forums — Bookworm X11/Wayland kiosk issues](https://forums.raspberrypi.com/viewtopic.php?t=380416) — 2025-2026 community reports of Wayland problems
- [Pi Forums — MQTT losing connection after many hours](https://forums.raspberrypi.com/viewtopic.php?t=311553) — paho-mqtt threading deadlock pattern
- [Dries Buytaert — Keeping Raspberry Pi online with watchdogs](https://dri.es/keeping-your-raspberry-pi-online-with-watchdogs) — WiFi watchdog patterns
- [reelyActive — Configure Raspberry Pi as kiosk display](https://reelyactive.github.io/diy/pi-kiosk/) — Architecture patterns
- [SmartUpWorld — Chromium Kiosk Mode Guide](https://smartupworld.com/chromium-kiosk-mode/) — Touch flags best practices

### Tertiary (LOW confidence, needs validation)
- [Pi Forums — WiFi Watchdog Scripts](https://forums.raspberrypi.com/viewtopic.php?t=313921) — Multiple cron approaches, implementation details vary
- [Building WPE for Pi 3 — Medium](https://samdecrock.medium.com/building-wpe-webkit-for-raspberry-pi-3-cdbd7b5cb362) — Alternative browser complexity (deferred)
- [Raspberry Pi Security Hardening Guide](https://ohyaan.github.io/tips/raspberry_pi_security_hardening_complete_guide/) — Advanced hardening (overlay FS, read-only root) — deferred to v2+

---
*Research completed: 2026-02-11*
*Ready for roadmap: yes*
