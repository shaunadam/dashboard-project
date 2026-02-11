---
phase: 01-centralized-configuration-core-fixes
plan: 02
subsystem: infra
tags: [config, bash, python, chromium-security, mqtt, kiosk, touchscreen, display]

# Dependency graph
requires:
  - phase: 01-01
    provides: "config.json.template, lib/config.sh, lib/config.py, functional directory layout"
provides:
  - "kiosk.sh consuming dashboard URL, timing, and paths from config.json"
  - "touchscreen-check.sh consuming USB device ID and parameters from config.json"
  - "mqtt_listener.py consuming broker, credentials, topics from config.json (no more mqtt.json)"
  - "display_control.py consuming wayland display name from config.json"
  - "ha_init.py consuming broker settings and topics from config.json"
  - "Chromium --disable-web-security flag removed (CLN-03)"
affects: [01-03, 01-04, 01-05]

# Tech tracking
tech-stack:
  added: []
  patterns: [config-driven-scripts, repo-root-resolution-pattern]

key-files:
  created: []
  modified:
    - kiosk/kiosk.sh
    - touchscreen/touchscreen-check.sh
    - display/display_control.py
    - mqtt/mqtt_listener.py
    - mqtt/ha_init.py

key-decisions:
  - "cfg_get with bash default fallback (${VAR:-default}) for optional values instead of passing defaults to cfg_get"
  - "REPO_ROOT derived from script location in every script (not environment variable)"
  - "mqtt_listener.py stores heartbeat_interval from config but does not implement heartbeat (deferred to Plan 03)"

patterns-established:
  - "Bash scripts: SCRIPT_DIR + REPO_ROOT derivation, then source lib/config.sh"
  - "Python scripts: REPO_ROOT via Path(__file__).resolve().parent.parent, sys.path.insert, from lib.config import"
  - "Optional config values use cfg_get with bash default (${VAR:-default}) or Python get(key, default)"
  - "Required config values use cfg_require / require which exit/raise on missing"

# Metrics
duration: 3min
completed: 2026-02-11
---

# Phase 1 Plan 2: Script Config Migration Summary

**All five scripts migrated to centralized config.json via shared loaders, removing hardcoded IPs/IDs/paths and the Chromium --disable-web-security flag (CLN-03)**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-11T19:16:12Z
- **Completed:** 2026-02-11T19:18:56Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Migrated kiosk.sh to load dashboard URL, desktop wait time, user data dir, and onboard size from config.json
- Removed --disable-web-security from Chromium flags (CLN-03 security fix)
- Migrated touchscreen-check.sh to load USB device ID, flag file path, log tag, and wait time from config.json
- Migrated mqtt_listener.py to load broker, port, credentials, topics, and client ID from config.json (eliminated separate mqtt.json dependency)
- Migrated display_control.py to load wayland display name from config.json
- Migrated ha_init.py to use centralized config (deviation fix -- would have broken at runtime)

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate bash scripts to centralized config** - `3b6c126` (feat)
2. **Task 2: Migrate Python scripts to centralized config** - `45d6b53` (feat)
3. **Deviation: Migrate ha_init.py to centralized config** - `ed11020` (fix)

## Files Created/Modified
- `kiosk/kiosk.sh` - Config-driven kiosk launcher; loads URL, timing, paths from config.json; --disable-web-security removed
- `touchscreen/touchscreen-check.sh` - Config-driven touchscreen checker; loads USB ID, flag file, log tag, wait time from config.json
- `display/display_control.py` - Config-driven display control; loads wayland display name from config.json
- `mqtt/mqtt_listener.py` - Config-driven MQTT listener; loads broker, port, credentials, topics, client ID from config.json
- `mqtt/ha_init.py` - Config-driven HA discovery publisher; loads broker settings and topics from config.json

## Decisions Made
- **cfg_get with bash default fallback:** Used `${VAR:-default}` pattern for optional bash config values rather than building default-support into cfg_get, keeping the loader simple
- **REPO_ROOT from script location:** Every script derives REPO_ROOT from its own file path, making scripts relocatable without environment variables
- **Heartbeat interval read but not used:** mqtt_listener.py reads heartbeat_interval_seconds from config and stores it as self.heartbeat_interval, but heartbeat logic is deferred to Plan 03

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Migrated ha_init.py to centralized config**
- **Found during:** Overall verification (post-Task 2)
- **Issue:** ha_init.py still referenced `config/mqtt.json` which no longer exists after the centralized config migration. Running it would fail with FileNotFoundError.
- **Fix:** Replaced mqtt.json loading with lib/config.py imports (get/require). Topics now loaded from config.json with defaults. Removed load_cfg function and CONFIG_FILE constant.
- **Files modified:** mqtt/ha_init.py
- **Verification:** `grep -r 'mqtt.json' mqtt/` returns nothing; `grep 'from lib.config import' mqtt/ha_init.py` confirms import
- **Committed in:** ed11020 (separate deviation commit)

---

**Total deviations:** 1 auto-fixed (1 missing critical)
**Impact on plan:** Essential fix to prevent runtime breakage. No scope creep -- same config migration pattern applied to missed file.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All scripts now consume config.json exclusively via shared loaders
- Plan 03 can implement MQTT heartbeat using the heartbeat_interval already stored in mqtt_listener.py
- Plan 04 (bootstrap rewrite) can generate config.json from config.json.template knowing all scripts expect centralized config
- Plan 05 (systemd services) can reference scripts at their new paths

## Self-Check: PASSED

All 5 modified files verified present. All 3 task commits (3b6c126, 45d6b53, ed11020) verified in git log.

---
*Phase: 01-centralized-configuration-core-fixes*
*Completed: 2026-02-11*
