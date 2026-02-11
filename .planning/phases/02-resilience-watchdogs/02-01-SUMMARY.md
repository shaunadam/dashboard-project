---
phase: 02-resilience-watchdogs
plan: 01
subsystem: infra
tags: [bash, nmcli, networkmanager, watchdog, wifi, systemd]

# Dependency graph
requires:
  - phase: 01-centralized-config
    provides: "lib/config.sh with cfg_get/cfg_require, config.json.template, touchscreen-check.sh flag-file pattern"
provides:
  - "watchdog/wifi-watchdog.sh: network check + staged recovery with flag-file boot-loop protection"
  - "config.json.template: watchdog config keys (reboot_flag_file_wifi, log_tag_wifi, log_tag_browser)"
affects: [02-02-browser-watchdog, 02-03-bootstrap-integration]

# Tech tracking
tech-stack:
  added: [nmcli, ping, host, curl]
  patterns: [multi-stage-network-validation, staged-recovery, flag-file-boot-loop-protection]

key-files:
  created: [watchdog/wifi-watchdog.sh]
  modified: [config.json.template]

key-decisions:
  - "WiFi watchdog uses separate flag file path from touchscreen (/var/run/wifi-reboot-attempted vs /var/run/touchscreen-reboot-attempted)"
  - "check_network returns success if ANY of 4 stages passes (optimistic, avoids false positives)"
  - "Recovery stages ordered by disruption: nmcli cycle < credential apply < NM restart < reboot"
  - "Signal file /tmp/wifi-recovered created after recovery for browser watchdog coordination"

patterns-established:
  - "Multi-stage network validation: gateway ping, DNS ping, DNS resolution, HTTP check"
  - "Staged recovery escalation: least disruptive first, reboot as absolute last resort"
  - "Watchdog config keys as optional cfg_get with hardcoded defaults (not cfg_require)"

# Metrics
duration: 3min
completed: 2026-02-11
---

# Phase 2 Plan 1: WiFi Watchdog Summary

**WiFi watchdog with 4-stage network validation, staged nmcli recovery, and flag-file boot-loop protection**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-11T21:50:07Z
- **Completed:** 2026-02-11T21:53:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created WiFi watchdog script with 4-stage network validation (gateway ping, DNS ping, DNS resolution, HTTP dashboard check)
- Implemented staged recovery escalation: nmcli connection cycle, credential apply from config, NetworkManager restart, system reboot as last resort
- Flag-file boot-loop protection using separate path from touchscreen watchdog
- Added watchdog config keys (reboot_flag_file_wifi, log_tag_wifi, log_tag_browser) to config.json.template

## Task Commits

Each task was committed atomically:

1. **Task 1: Create WiFi watchdog script** - `e3dd579` (feat)
2. **Task 2: Add watchdog config keys to template** - `ca3e8ce` (feat)

## Files Created/Modified
- `watchdog/wifi-watchdog.sh` - Network check + multi-stage recovery with flag-file reboot protection
- `config.json.template` - Added reboot_flag_file_wifi, log_tag_wifi, log_tag_browser in system section

## Decisions Made
- WiFi watchdog uses separate flag file `/var/run/wifi-reboot-attempted` (not shared with touchscreen's `/var/run/touchscreen-reboot-attempted`) to prevent coordination conflicts
- check_network() returns 0 (success) if ANY of the 4 stages passes -- optimistic approach avoids unnecessary recovery when partial connectivity exists
- Recovery stages ordered by increasing disruption level: nmcli down/up cycle first, credential reapply second, full NetworkManager restart third, system reboot only as last resort with flag-file protection
- Signal file `/tmp/wifi-recovered` touched after successful recovery for Plan 02's browser watchdog to detect and trigger page reload

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- WiFi watchdog script is ready for systemd timer integration in Plan 03
- Browser watchdog (Plan 02) can check `/tmp/wifi-recovered` signal file for post-recovery reload
- All config keys use sensible defaults via cfg_get with bash fallback pattern

## Self-Check: PASSED

- [x] watchdog/wifi-watchdog.sh exists
- [x] config.json.template exists
- [x] 02-01-SUMMARY.md exists
- [x] Commit e3dd579 exists (Task 1)
- [x] Commit ca3e8ce exists (Task 2)

---
*Phase: 02-resilience-watchdogs*
*Completed: 2026-02-11*
