# Requirements: Dashboard Kiosk Hardening

**Defined:** 2026-02-11
**Core Value:** The dashboard must boot from cold power-on to showing the week planner page with working touchscreen and zero human intervention.

## v1 Requirements

Requirements for hardening milestone. Each maps to roadmap phases.

### Configuration Management

- [ ] **CFG-01**: Zero magic numbers or hardcoded parameters in any script — all values consumed from a single centralized JSON config file
- [ ] **CFG-02**: Dashboard URL loaded from centralized config (removed from kiosk.sh)
- [ ] **CFG-03**: MQTT broker settings loaded from centralized config (replaces separate mqtt.json)
- [ ] **CFG-04**: USB touchscreen device ID loaded from centralized config (removed from touchscreen-check.sh)
- [ ] **CFG-05**: WiFi credentials stored in centralized config for watchdog use
- [ ] **CFG-06**: HA authentication method configurable in centralized config
- [ ] **CFG-07**: Inactivity timeout (for auto-return) configurable in centralized config
- [ ] **CFG-08**: Scheduled reboot interval configurable in centralized config
- [ ] **CFG-09**: Config backup script exports rendered config to user-specified location
- [ ] **CFG-10**: Config restore script imports backup and applies to system
- [ ] **CFG-11**: Bootstrap script renders config template from user-prompted values
- [ ] **CFG-12**: Recovery documentation clearly states config backup is required for fast recovery

### Network Resilience

- [ ] **NET-01**: WiFi watchdog detects network connectivity loss automatically
- [ ] **NET-02**: WiFi watchdog authoritatively applies WiFi credentials from config file (overwriting any manually-entered credentials on the system)
- [ ] **NET-03**: Multi-stage validation (gateway ping → DNS resolution → HTTP check) before declaring failure
- [ ] **NET-04**: WiFi watchdog uses flag-file boot-loop protection (same pattern as touchscreen-check.sh)
- [ ] **NET-05**: Browser automatically reloads dashboard page after network recovery
- [ ] **NET-06**: Watchdog services are coordinated to avoid conflicts with touchscreen reboot and each other

### Browser UX

- [ ] **BRW-01**: User can touch-drag to scroll the HA dashboard vertically (no text selection on drag) — try Chromium flags first, explore alternative browser only if flags fail on hardware
- [ ] **BRW-02**: Chromium auto-restarts on crash via systemd service supervision
- [ ] **BRW-03**: Browser returns to week planner page after configurable inactivity period (default 10 minutes)
- [ ] **BRW-04**: System performs scheduled soft reboot at configurable interval (default every 2-3 days)
- [ ] **BRW-05**: No "restore pages?" dialog appears after crash recovery or reboot

### MQTT & Display Integration

- [ ] **MQTT-01**: Display status command returns actual display power state (not placeholder)
- [ ] **MQTT-02**: paho-mqtt dependency installed automatically by bootstrap script
- [ ] **MQTT-03**: HA discovery registers display entities with correct device info and capabilities
- [ ] **MQTT-04**: MQTT listener publishes periodic heartbeat so HA can detect zombie connections

### Project Cleanup & Structure

- [ ] **CLN-01**: Diagnostic scripts removed (diagnose-usb.sh, usb-rescan.sh)
- [ ] **CLN-02**: KidChores references removed from codebase
- [ ] **CLN-03**: --disable-web-security flag removed from Chromium launch (replaced with proper approach)
- [ ] **CLN-04**: Project files reorganized into logical directory structure following best practices

### Testing

- [ ] **TST-01**: Unit tests for MQTT listener cover message parsing, command handling, and reconnection logic
- [ ] **TST-02**: Unit tests for display control cover command execution and error handling
- [ ] **TST-03**: All unit tests run on developer laptop (Windows) without Pi hardware

## v2 Requirements

Deferred to future milestone. Tracked but not in current roadmap.

### Testing (Extended)

- **TST-04**: ShellCheck linting for all bash scripts
- **TST-05**: bats-core tests for shell scripts (touchscreen-check, kiosk launcher, bootstrap)
- **TST-06**: Unit tests for bootstrap template rendering

### Monitoring

- **MON-01**: Basic system monitoring (CPU temp, disk space, service status)
- **MON-02**: Health check dashboard accessible via local web UI

### Browser (Extended)

- **BRW-06**: Periodic page refresh to prevent stale cached data
- **BRW-07**: Touchscreen calibration verification

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Fundamental changes to touchscreen cold→soft reboot pattern | Took extensive debugging to get working; risk not worth any optimization |
| Multi-Pi dashboard support | Single Pi deployment; no need for parameterized device identifiers |
| Docker deployment on Pi | Pi 4 has limited resources; adds complexity without clear value |
| Mobile app | Web dashboard on Pi touchscreen is the product |
| CI/CD automated deployment | Overkill for single Pi; git pull + bootstrap is sufficient |
| Read-only filesystem | Breaking change; blocks logs, configs, caching; proper shutdown is better for family use |
| OTA firmware updates | Risk of bricking kiosk; manual update schedule is safer |
| Wayland migration | Current X11 setup works; Wayland kiosk mode unreliable per 2025-2026 community reports |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CFG-01 | — | Pending |
| CFG-02 | — | Pending |
| CFG-03 | — | Pending |
| CFG-04 | — | Pending |
| CFG-05 | — | Pending |
| CFG-06 | — | Pending |
| CFG-07 | — | Pending |
| CFG-08 | — | Pending |
| CFG-09 | — | Pending |
| CFG-10 | — | Pending |
| CFG-11 | — | Pending |
| CFG-12 | — | Pending |
| NET-01 | — | Pending |
| NET-02 | — | Pending |
| NET-03 | — | Pending |
| NET-04 | — | Pending |
| NET-05 | — | Pending |
| NET-06 | — | Pending |
| BRW-01 | — | Pending |
| BRW-02 | — | Pending |
| BRW-03 | — | Pending |
| BRW-04 | — | Pending |
| BRW-05 | — | Pending |
| MQTT-01 | — | Pending |
| MQTT-02 | — | Pending |
| MQTT-03 | — | Pending |
| MQTT-04 | — | Pending |
| CLN-01 | — | Pending |
| CLN-02 | — | Pending |
| CLN-03 | — | Pending |
| CLN-04 | — | Pending |
| TST-01 | — | Pending |
| TST-02 | — | Pending |
| TST-03 | — | Pending |

**Coverage:**
- v1 requirements: 33 total
- Mapped to phases: 0
- Unmapped: 33

---
*Requirements defined: 2026-02-11*
*Last updated: 2026-02-11 after initial definition*
