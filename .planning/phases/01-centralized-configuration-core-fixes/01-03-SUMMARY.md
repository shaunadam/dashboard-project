---
phase: 01-centralized-configuration-core-fixes
plan: 03
subsystem: display, mqtt
tags: [wlopm, mqtt-discovery, home-assistant, heartbeat, display-control]

# Dependency graph
requires:
  - phase: 01-01
    provides: "Centralized config.json with lib/config.py loader, functional directory layout"
  - phase: 01-02
    provides: "Scripts migrated to use centralized config via lib/config.py"
provides:
  - "display_control.py with real hardware status query via wlopm"
  - "mqtt_listener.py with HA MQTT auto-discovery payload for automatic switch entity"
  - "mqtt_listener.py with periodic heartbeat for zombie connection detection"
  - "Consistent status output format (Display is on/off/unknown) across all commands"
affects: [01-04, 01-05]

# Tech tracking
tech-stack:
  added: []
  patterns: [mqtt-auto-discovery, heartbeat-availability, hardware-status-verification]

key-files:
  created: []
  modified:
    - display/display_control.py
    - mqtt/mqtt_listener.py

key-decisions:
  - "Parse actual display state from wlopm output rather than assuming command success"
  - "Publish verified hardware state for on/off commands (not just echo back the command)"
  - "Discovery payload uses retain=True so HA discovers entity even after broker restart"

patterns-established:
  - "display_control.py outputs 'Display is {state}' for all commands (on, off, status)"
  - "mqtt_listener.py parses display_control.py output consistently using 'is on'/'is off' matching"
  - "Heartbeat re-publishes availability at configurable interval from mqtt.heartbeat_interval_seconds"

# Metrics
duration: 2min
completed: 2026-02-11
---

# Phase 1 Plan 3: Display Status & MQTT Discovery Summary

**Real display status query via wlopm, HA MQTT auto-discovery for automatic switch entity creation, and periodic heartbeat for zombie connection detection**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-11T19:21:06Z
- **Completed:** 2026-02-11T19:23:13Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Replaced placeholder status with real hardware query via wlopm (MQTT-01 closed)
- Added HA MQTT auto-discovery publishing a switch entity config to homeassistant/switch/dashboard_display/config on connect (MQTT-03 closed)
- Added periodic heartbeat re-publishing availability at configurable interval so HA detects zombie MQTT connections (MQTT-04 closed)
- Unified status output format: all commands now output "Display is {on|off|unknown}" and mqtt_listener parses actual state consistently

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement real display status query** - `ea8405a` (feat)
2. **Task 2: Add MQTT auto-discovery and heartbeat** - `b904a99` (feat)

## Files Created/Modified
- `display/display_control.py` - Added get_status() function querying wlopm for real hardware state; status command uses it; on/off commands verify actual state after execution
- `mqtt/mqtt_listener.py` - Added _publish_discovery() for HA auto-discovery, _publish_heartbeat() for periodic availability, updated _handle_command to parse actual state from display_control.py output

## Decisions Made
- **Parse actual state, not assumed state:** After Task 1 made display_control.py verify hardware state for on/off commands, updated mqtt_listener's _handle_command to parse the actual output rather than publishing the command name. This ensures HA always shows real hardware state.
- **Discovery payload retained:** Using retain=True on the discovery topic so HA can discover the entity even if it restarts after the Pi publishes.
- **Heartbeat as availability re-publish:** Simple approach -- re-publish "online" to availability topic at interval. If it stops, HA's MQTT integration detects the entity as unavailable via the existing LWT mechanism.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated _handle_command to parse actual state instead of echoing command**
- **Found during:** Task 2 (MQTT auto-discovery and heartbeat)
- **Issue:** After Task 1 changed display_control.py to output verified hardware state ("Display is {actual}") for on/off commands, _handle_command was still publishing the command name directly (e.g., publishing "on" without checking if the display actually turned on)
- **Fix:** Changed _handle_command to parse display_control.py stdout using the same 'is on'/'is off' pattern as _publish_current_status
- **Files modified:** mqtt/mqtt_listener.py
- **Verification:** grep confirms consistent parsing pattern in both _handle_command and _publish_current_status
- **Committed in:** b904a99 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential for correctness -- HA must show real hardware state, not assumed state. Aligns with user decision: "Positive confirmation is better than implying a command worked."

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- display_control.py and mqtt_listener.py are fully updated with real status, discovery, and heartbeat
- Bootstrap script (Plan 04) needs to handle systemd service files for the updated mqtt_listener
- Verify script (Plan 05) can validate discovery payload format and heartbeat behavior
- MQTT-01, MQTT-03, MQTT-04 blockers from STATE.md are now resolved

## Self-Check: PASSED

All 2 modified files verified present. Both task commits (ea8405a, b904a99) verified in git log.

---
*Phase: 01-centralized-configuration-core-fixes*
*Completed: 2026-02-11*
