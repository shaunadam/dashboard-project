# Roadmap: Dashboard Kiosk Hardening

## Overview

Transform a functional Raspberry Pi kiosk into a production-hardened 24/7 family dashboard. The journey starts with foundational configuration management that eliminates hardcoded values and enables fast disaster recovery, then layers automated resilience mechanisms for network and browser failures, and finishes with comprehensive testing and codebase cleanup to prevent regressions and improve maintainability.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Centralized Configuration & Core Fixes** - Config foundation plus broken display control and MQTT status
- [ ] **Phase 2: Resilience & Watchdogs** - WiFi watchdog, browser crash recovery, service coordination
- [ ] **Phase 3: Testing & Cleanup** - Unit tests, integration tests, remove legacy code

## Phase Details

### Phase 1: Centralized Configuration & Core Fixes
**Goal**: Single source of truth for all configuration and working display control integration with Home Assistant
**Depends on**: Nothing (first phase)
**Requirements**: CFG-01, CFG-02, CFG-03, CFG-04, CFG-05, CFG-06, CFG-07, CFG-08, CFG-09, CFG-10, CFG-11, CFG-12, MQTT-01, MQTT-02, MQTT-03, MQTT-04, CLN-03, CLN-04
**Success Criteria** (what must be TRUE):
  1. All scripts load configuration from single centralized JSON file with zero hardcoded values
  2. Bootstrap script prompts for all config values and renders working config file
  3. Config backup script exports configuration to user-specified location
  4. Config restore script applies backup and system works immediately
  5. Home Assistant display switch entity shows actual display power state, not placeholder
  6. Display control commands work reliably with modern KMS drivers
  7. MQTT discovery registers display entity with correct capabilities
  8. Chromium launches without security vulnerabilities (no --disable-web-security flag)
  9. Project files reorganized into logical directory structure (all new code goes in the right place from the start)
**Plans**: 5 plans in 3 waves

Plans:
- [ ] 01-01-PLAN.md — Directory restructure + centralized config schema + loader libraries
- [ ] 01-02-PLAN.md — Migrate all scripts to load from centralized config + remove --disable-web-security
- [ ] 01-03-PLAN.md — Display status fix + MQTT auto-discovery + heartbeat
- [ ] 01-04-PLAN.md — Bootstrap and verify rewrite for new structure
- [ ] 01-05-PLAN.md — Config backup/restore + branch-switch script + readme update + Pi verification

### Phase 2: Resilience & Watchdogs
**Goal**: Automated recovery from network failures and browser crashes with zero human intervention
**Depends on**: Phase 1
**Requirements**: NET-01, NET-02, NET-03, NET-04, NET-05, NET-06, BRW-01, BRW-02, BRW-03, BRW-04, BRW-05
**Success Criteria** (what must be TRUE):
  1. WiFi watchdog detects network failures and reconnects using configured credentials
  2. WiFi watchdog uses flag-file protection to prevent infinite reboot loops
  3. Browser automatically reloads dashboard page after network recovery
  4. Chromium crashes are invisible to users (auto-restart via systemd supervision)
  5. System returns to week planner page after configurable inactivity timeout
  6. System performs scheduled soft reboots at configurable intervals without manual intervention
  7. No "restore pages?" dialogs appear after crash or reboot
  8. Touch-drag scrolls vertically without text selection
  9. Watchdog services coordinate to avoid conflicts with touchscreen reboot mechanism
**Plans**: TBD

Plans:
- [ ] 02-01: [TBD during planning]
- [ ] 02-02: [TBD during planning]

### Phase 3: Testing & Cleanup
**Goal**: Comprehensive test coverage and clean codebase ready for long-term maintenance
**Depends on**: Phase 2
**Requirements**: TST-01, TST-02, TST-03, CLN-01, CLN-02
**Success Criteria** (what must be TRUE):
  1. Unit tests for MQTT listener run on Windows laptop without Pi hardware
  2. Unit tests for display control run on Windows laptop without Pi hardware
  3. All unit tests pass with mocked hardware dependencies
  4. Integration tests document which features require real Pi for validation
  5. Diagnostic scripts removed from codebase (diagnose-usb.sh, usb-rescan.sh)
  6. KidChores references removed from all files
**Plans**: TBD

Plans:
- [ ] 03-01: [TBD during planning]

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Centralized Configuration & Core Fixes | 0/5 | Not started | - |
| 2. Resilience & Watchdogs | 0/TBD | Not started | - |
| 3. Testing & Cleanup | 0/TBD | Not started | - |
