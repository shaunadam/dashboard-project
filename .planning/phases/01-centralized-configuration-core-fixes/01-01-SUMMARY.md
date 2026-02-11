---
phase: 01-centralized-configuration-core-fixes
plan: 01
subsystem: infra
tags: [json, jq, config, bash, python, directory-structure]

# Dependency graph
requires: []
provides:
  - "config.json.template with all configurable values as __TOKEN__ placeholders"
  - "lib/config.sh bash config loader (cfg_get, cfg_require via jq)"
  - "lib/config.py python config loader (get, require with dot-notation)"
  - "Functional directory layout: kiosk/, display/, mqtt/, touchscreen/, setup/, lib/"
affects: [01-02, 01-03, 01-04, 01-05]

# Tech tracking
tech-stack:
  added: [jq]
  patterns: [centralized-json-config, functional-directory-grouping, config-loader-library]

key-files:
  created:
    - config.json.template
    - lib/config.sh
    - lib/config.py
  modified:
    - .gitignore
    - CLAUDE.md
    - readme.md

key-decisions:
  - "Nested JSON config grouped by concern (dashboard, mqtt, display, touchscreen, kiosk, wifi, home_assistant, browser, system)"
  - "Config loaders as shared libraries in lib/ (not per-script config loading)"
  - "Moved ha-init.py from config/systemd/ to mqtt/ since it is an MQTT discovery script"

patterns-established:
  - "cfg_get/cfg_require for bash scripts sourcing lib/config.sh"
  - "get/require with dot-notation for python scripts importing lib/config.py"
  - "Functional directories: group files by what they DO (kiosk/, display/, mqtt/, etc.)"
  - "config.json.template at repo root with __TOKEN__ placeholders; config.json git-ignored"

# Metrics
duration: 4min
completed: 2026-02-11
---

# Phase 1 Plan 1: Project Restructure & Config Foundation Summary

**Centralized config.json.template with 9 configurable sections, bash/python config loader libraries, and full project restructure into functional directories**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-11T19:09:28Z
- **Completed:** 2026-02-11T19:13:36Z
- **Tasks:** 2
- **Files modified:** 17

## Accomplishments
- Created config.json.template defining the complete configuration schema (dashboard, mqtt, display, touchscreen, kiosk, wifi, home_assistant, browser, system)
- Built bash config loader (lib/config.sh) with jq-based cfg_get/cfg_require functions
- Built python config loader (lib/config.py) with dot-notation get/require and caching
- Restructured entire project from flat scripts/ layout into functional directories (kiosk/, display/, mqtt/, touchscreen/, setup/, lib/)
- Removed old template files (kiosk.desktop, systemd services, mqtt.json.template) -- bootstrap will generate these programmatically
- Updated CLAUDE.md and readme.md with new directory layout and paths

## Task Commits

Each task was committed atomically:

1. **Task 1: Create centralized config template and loader libraries** - `6a925e3` (feat)
2. **Task 2: Restructure project into functional directories** - `5592612` (feat)

## Files Created/Modified
- `config.json.template` - Centralized config template with __TOKEN__ placeholders for all configurable values
- `lib/config.sh` - Bash config loader: cfg_get (jq extraction), cfg_require (fail on missing)
- `lib/config.py` - Python config loader: load_config, get (dot-notation), require (fail on missing), ConfigError
- `.gitignore` - Added config.json at repo root
- `kiosk/kiosk.sh` - Moved from scripts/kiosk.sh (content unchanged)
- `display/display_control.py` - Moved from scripts/display_control.py (content unchanged)
- `mqtt/mqtt_listener.py` - Moved from scripts/mqtt_listener.py (content unchanged)
- `mqtt/ha_init.py` - Moved from config/systemd/ha-init.py (content unchanged)
- `touchscreen/touchscreen-check.sh` - Moved from scripts/touchscreen-check.sh (content unchanged)
- `setup/bootstrap.sh` - Moved from scripts/setup/bootstrap.sh (content unchanged)
- `setup/verify.sh` - Moved from scripts/setup/verify.sh (content unchanged)
- `CLAUDE.md` - Rewritten with new directory structure and config access patterns
- `readme.md` - Updated project structure diagram and all path references

## Decisions Made
- **Nested JSON structure grouped by concern:** 9 top-level sections covering all configurable values across the project. Port is numeric (unquoted __MQTT_PORT__), topics included to avoid hardcoding in scripts.
- **Config loaders as shared libraries:** lib/config.sh and lib/config.py provide the single interface to config.json. Scripts source/import these rather than loading config themselves.
- **ha-init.py relocated to mqtt/:** Found in config/systemd/ which was being deleted. Moved to mqtt/ since it publishes MQTT discovery payloads.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Moved ha-init.py from config/systemd/ to mqtt/**
- **Found during:** Task 2 (Restructure project)
- **Issue:** config/systemd/ha-init.py would be orphaned when config/systemd/ directory was removed. This file was not mentioned in the plan.
- **Fix:** git mv config/systemd/ha-init.py mqtt/ha_init.py (MQTT discovery script belongs with MQTT code)
- **Files modified:** mqtt/ha_init.py (renamed)
- **Verification:** File exists at new location, git tracks rename
- **Committed in:** 5592612 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Necessary to prevent file loss. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Directory structure is in place for Plans 02-05 to update script contents
- Config loaders ready for scripts to consume (Plan 02 will wire kiosk.sh, Plan 03 will wire mqtt_listener.py and display_control.py)
- Bootstrap needs rewriting in Plan 04 to generate config.json from template and create systemd/autostart files programmatically
- Old scripts/ directory still contains diagnose-usb.sh and usb-rescan.sh (Phase 3 cleanup)

## Self-Check: PASSED

All 11 created/modified files verified present. Both task commits (6a925e3, 5592612) verified in git log.

---
*Phase: 01-centralized-configuration-core-fixes*
*Completed: 2026-02-11*
