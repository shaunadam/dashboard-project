---
phase: 02-resilience-watchdogs
plan: 02
subsystem: kiosk
tags: [chromium, touch, xprintidle, xdotool, crash-recovery, watchdog]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "lib/config.sh with cfg_get/cfg_require, config.json.template with browser section"
  - phase: 02-resilience-watchdogs plan 01
    provides: "WiFi watchdog with /tmp/wifi-recovered signal file"
provides:
  - "Hardened kiosk launcher with touch flags, crash cleanup, restart loop"
  - "Browser watchdog daemon for idle auto-return and WiFi recovery reload"
affects: [02-resilience-watchdogs plan 03]

# Tech tracking
tech-stack:
  added: [xprintidle, xdotool]
  patterns: [restart-loop-crash-recovery, signal-file-coordination, chromium-preferences-sed-cleanup]

key-files:
  created:
    - watchdog/browser-watchdog.sh
  modified:
    - kiosk/kiosk.sh

key-decisions:
  - "F5 reload for idle auto-return (simpler than URL navigation, sufficient for HA dashboards)"
  - "Restart loop in kiosk.sh rather than systemd service supervision (avoids X11 session complexity)"
  - "Chromium flags-first approach for touch scrolling (--disable-touch-drag-drop, --disable-pinch)"

patterns-established:
  - "Restart loop: while-true wrapper around Chromium launch with sleep between restarts"
  - "Signal file coordination: /tmp/wifi-recovered bridges wifi-watchdog and browser-watchdog"
  - "Preferences sed cleanup: exited_cleanly + exit_type reset before every Chromium launch"

# Metrics
duration: 2min
completed: 2026-02-11
---

# Phase 2 Plan 2: Browser Kiosk Hardening Summary

**Hardened Chromium kiosk with touch flags, crash-state cleanup, restart loop, plus browser watchdog for idle auto-return and WiFi recovery reload via xprintidle/xdotool**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-11T21:54:08Z
- **Completed:** 2026-02-11T21:55:41Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Kiosk launcher hardened with --disable-touch-drag-drop, --overscroll-history-navigation=0, --disable-pinch to prevent text selection and accidental gestures on touchscreen
- Chromium Preferences file cleaned (exited_cleanly/exit_type) before every launch to eliminate "restore pages?" dialog
- While-true restart loop ensures Chromium auto-restarts after any crash with 5-second backoff
- Browser watchdog monitors idle time via xprintidle and reloads dashboard after configurable timeout (default 600s)
- WiFi recovery signal file (/tmp/wifi-recovered) triggers browser reload after network restoration

## Task Commits

Each task was committed atomically:

1. **Task 1: Harden kiosk.sh with touch flags, crash cleanup, and restart loop** - `787f969` (feat)
2. **Task 2: Create browser watchdog for idle auto-return and WiFi recovery reload** - `f7f2211` (feat)

## Files Created/Modified
- `kiosk/kiosk.sh` - Hardened kiosk launcher with touch flags, Preferences cleanup, restart loop
- `watchdog/browser-watchdog.sh` - Long-running daemon for idle detection and WiFi recovery reload

## Decisions Made
- Used F5 reload (xdotool key F5) for idle auto-return rather than URL bar navigation -- simpler and sufficient for HA dashboards that reset to default view on reload
- Kept restart loop approach in kiosk.sh rather than converting to systemd service supervision -- avoids X11 session integration complexity per research recommendation
- Applied Chromium flags-first approach for touch UX (--disable-touch-drag-drop, --disable-pinch, --overscroll-history-navigation=0) -- CSS injection deferred unless flags fail on hardware

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required. xprintidle package will be installed by bootstrap.sh (Plan 03 systemd integration).

## Next Phase Readiness
- kiosk.sh and browser-watchdog.sh ready for systemd service integration in Plan 03
- Both scripts follow project conventions (cfg_get/cfg_require, logger -t, SCRIPT_DIR/REPO_ROOT)
- Signal file coordination between wifi-watchdog.sh and browser-watchdog.sh is in place

## Self-Check: PASSED

All files verified present. All commit hashes verified in git log.

---
*Phase: 02-resilience-watchdogs*
*Completed: 2026-02-11*
