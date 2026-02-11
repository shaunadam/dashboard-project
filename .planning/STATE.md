# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-11)

**Core value:** The dashboard must boot from cold power-on to showing the week planner page with working touchscreen and zero human intervention.
**Current focus:** Phase 2 in progress — Resilience & Watchdogs

## Current Position

Phase: 2 of 3 (Resilience & Watchdogs)
Plan: 2/3 complete
Status: Executing Phase 2 plans
Last activity: 2026-02-11 — Completed 02-02 Browser kiosk hardening

Progress: [█████░░░░░] 50%

## Performance Metrics

**Velocity:**
- Total plans completed: 7
- Average duration: 2min
- Total execution time: 0.30 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 5 | 13min | 3min |
| 02 | 2 | 5min | 3min |

**Recent Trend:**
- Last 5 plans: 01-03 (2min), 01-04 (2min), 01-05 (2min), 02-01 (3min), 02-02 (2min)
- Trend: Stable/Improving

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Centralized config over environment variables (single config file easier for single-Pi deployment)
- Keep cold→soft reboot pattern for touchscreen (working solution, risk not worth optimization)
- Develop on laptop, deploy via git pull (simple workflow, no local simulation needed)
- Nested JSON config grouped by concern: 9 sections covering all configurable values (01-01)
- Config loaders as shared libraries in lib/ rather than per-script config loading (01-01)
- ha-init.py relocated from config/systemd/ to mqtt/ (MQTT discovery belongs with MQTT code) (01-01)
- cfg_get with bash default fallback (${VAR:-default}) for optional values (01-02)
- REPO_ROOT derived from script location in every script, not environment variable (01-02)
- Heartbeat interval read from config but not implemented yet (deferred to Plan 03) (01-02)
- Parse actual display state from wlopm output, not assumed command success (01-03)
- Publish verified hardware state for on/off commands via consistent output parsing (01-03)
- Discovery payload uses retain=True so HA discovers entity even after broker restart (01-03)
- Generate systemd/autostart files programmatically from paths, no template files in repo (01-04)
- Use jq for config.json generation to safely handle special characters in passwords (01-04)
- Advanced config values use sensible defaults without prompting (01-04)
- Config restore validates JSON structure and required keys before overwriting config.json (01-05)
- Branch switch regenerates systemd service files to handle path differences between branches (01-05)
- HA automation examples updated to use switch entity (auto-discovered) instead of mqtt.publish (01-05)
- WiFi watchdog uses separate flag file from touchscreen (/var/run/wifi-reboot-attempted) to prevent coordination conflicts (02-01)
- check_network returns success if ANY of 4 stages passes (optimistic, avoids false recovery triggers) (02-01)
- Recovery ordered by disruption: nmcli cycle < credential apply < NM restart < reboot (02-01)
- Signal file /tmp/wifi-recovered used for browser watchdog coordination after recovery (02-01)
- F5 reload for idle auto-return rather than URL navigation (simpler, sufficient for HA dashboards) (02-02)
- Restart loop in kiosk.sh rather than systemd service supervision (avoids X11 session complexity) (02-02)
- Chromium flags-first approach for touch scrolling (--disable-touch-drag-drop, --disable-pinch) (02-02)

### Pending Todos

None yet.

### Blockers/Concerns

**Phase 1:**
- ~~Display control currently using vcgencmd which is broken by KMS driver~~ RESOLVED: display_control.py now uses wlopm for status query and on/off control (01-03)
- ~~MQTT status reporting may return placeholder instead of actual state~~ RESOLVED: display_control.py queries real hardware state, mqtt_listener parses actual output (01-03)
- ~~Chromium security flags need audit~~ RESOLVED: --disable-web-security removed in 01-02 (CLN-03)

## Session Continuity

Last session: 2026-02-11
Stopped at: Completed 02-02-PLAN.md (Browser kiosk hardening)
Resume file: None
