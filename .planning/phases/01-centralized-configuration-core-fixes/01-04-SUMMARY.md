---
phase: 01-centralized-configuration-core-fixes
plan: 04
subsystem: infra
tags: [bootstrap, provisioning, jq, config-generation, systemd, paho-mqtt, verify]

# Dependency graph
requires:
  - phase: 01-02
    provides: "Scripts migrated to centralized config via lib/config.sh and lib/config.py"
  - phase: 01-03
    provides: "display_control.py with wlopm status, mqtt_listener.py with discovery and heartbeat"
provides:
  - "bootstrap.sh that prompts for all config values and generates config.json via jq"
  - "bootstrap.sh that generates systemd unit files and autostart entry programmatically (no templates)"
  - "bootstrap.sh that installs paho-mqtt (MQTT-02) and jq"
  - "verify.sh that validates config.json, lib/ files, new script paths, and jq availability"
affects: [01-05]

# Tech tracking
tech-stack:
  added: []
  patterns: [programmatic-service-generation, jq-config-generation, comprehensive-provisioning]

key-files:
  created: []
  modified:
    - setup/bootstrap.sh
    - setup/verify.sh

key-decisions:
  - "Generate systemd unit files and autostart entry programmatically from paths (no template files in repo)"
  - "Use jq for config.json generation to safely handle special characters in passwords and values"
  - "Advanced config values (topics, heartbeat, timing) use sensible defaults without prompting"

patterns-established:
  - "bootstrap.sh is the single provisioning command for fresh Pi setup"
  - "verify.sh validates every component of the project structure end-to-end"
  - "Service files generated at install time from REPO_ROOT paths (not from templates with tokens)"

# Metrics
duration: 2min
completed: 2026-02-11
---

# Phase 1 Plan 4: Bootstrap & Verify Rewrite Summary

**Bootstrap rewritten to prompt for all config values, generate config.json via jq, and create systemd/autostart files programmatically; verify rewritten to validate new project structure end-to-end**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-11T19:25:54Z
- **Completed:** 2026-02-11T19:27:52Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Rewrote bootstrap.sh to prompt for all configuration values (dashboard URL, MQTT broker/port/username/password, touchscreen USB ID, Chromium data dir, WiFi SSID/password) and generate config.json using jq for proper JSON escaping
- Bootstrap now generates systemd unit files (touchscreen-check.service, mqtt-listener.service) and autostart entry (kiosk.desktop) programmatically from REPO_ROOT paths -- no template files with __TOKENS__ needed
- Enabled paho-mqtt installation (previously commented out, closing MQTT-02)
- Added jq to APT_PACKAGES for bash config loading support
- Removed Docker installation (out of scope per PROJECT.md)
- Rewrote verify.sh to validate config.json existence and required keys, lib/ files presence, autostart referencing correct kiosk path, all scripts at new locations, display_control.py check (new), and jq availability

## Task Commits

Each task was committed atomically:

1. **Task 1: Rewrite bootstrap.sh for new structure** - `9b52f00` (feat)
2. **Task 2: Rewrite verify.sh for new structure** - `b33b1da` (feat)

## Files Created/Modified
- `setup/bootstrap.sh` - Full provisioning script: apt packages (with jq), paho-mqtt install, config.json generation via jq prompts, programmatic autostart/systemd generation, updated script paths
- `setup/verify.sh` - Comprehensive verification: config.json validation (syntax + required keys), lib/ files check, autostart path check, all scripts at new functional directory paths, display_control.py check, jq command check

## Decisions Made
- **Programmatic service generation:** Systemd unit files and autostart entry are generated directly in bootstrap.sh using heredocs with REPO_ROOT substitution. No template files with __TOKENS__ exist in the repo -- bootstrap is the source of truth for service configuration.
- **jq for config generation:** Using jq -n with --arg for all string values ensures proper JSON escaping of special characters in passwords, URLs, and paths. Port uses --argjson for numeric type.
- **Sensible defaults without prompting:** MQTT topics, heartbeat interval, wayland display name, timing values, reboot flag path, and log tag all use sensible defaults. Users who need to change these can edit config.json directly after generation.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Bootstrap and verify are the final provisioning pieces for the new project structure
- Plan 05 (if any remaining) can build on the complete provisioning pipeline
- The full workflow (git clone -> bootstrap.sh -> verify.sh) now works end-to-end with the new directory layout
- All CFG-11 (bootstrap renders config) and MQTT-02 (paho-mqtt installed) requirements are satisfied

## Self-Check: PASSED
