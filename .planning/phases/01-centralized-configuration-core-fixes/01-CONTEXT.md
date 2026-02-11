# Phase 1: Centralized Configuration & Core Fixes - Context

**Gathered:** 2026-02-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Single source of truth for all configuration (replacing scattered hardcoded values and separate config files), working display control integration with Home Assistant, correct MQTT status reporting, and project files reorganized into a logical directory structure. Bootstrap script generates config and sets up services. Chromium security flags audited.

</domain>

<decisions>
## Implementation Decisions

### Config file design
- Single centralized `config.json` at repo root (git-ignored)
- Nested JSON structure grouped by concern (e.g., `{"mqtt": {...}, "display": {...}, "kiosk": {...}}`)
- Everything centralized — MQTT creds, dashboard URL, USB IDs, timing values, file paths — zero hardcoded values in scripts
- Existing `mqtt.json` absorbed into `config.json` under the `mqtt` section — one file replaces both
- `config.json.template` with `__TOKENS__` committed to repo for reference and bootstrap use
- Bootstrap script prompts for values and generates `config.json`

### Directory reorganization
- Full restructure into functional groupings (kiosk/, display/, mqtt/, setup/) — grouped by what the file DOES, not what it IS
- Bootstrap generates systemd unit files and autostart configs programmatically from `config.json` — no template files with `__TOKENS__` in repo
- Bootstrap handles all path updates when files move — re-run bootstrap after restructure
- All new Phase 1 code goes into the new structure from the start

### Display control
- Keep current display on/off behavior as-is — it's working today (HA -> MQTT -> Pi -> display toggle confirmed functional)
- If vcgencmd turns out to be what's working despite KMS, keep it; if research finds it's actually using something else, document what's real
- If a change is needed, Claude picks the best KMS-compatible tool — but note alternatives tried in case we need to iterate
- Status reporting should reflect actual hardware state (query display, not just remember last command) — standard HA integration pattern
- MQTT auto-discovery so HA automatically creates the display switch entity without manual configuration.yaml edits

### Dev/production workflow
- Work in a feature branch, main = production
- `git checkout` to switch between dev and production on the Pi
- Auto-restart script: one command to switch branch + restart affected services + verify
- Config is git-ignored, so it persists across branch switches — but since current main has no config.json, bootstrap must be re-run when switching to the new-structure branch
- When Phase 1 is tested, merge dev branch into main (standard merge, clean history)

### Claude's Discretion
- Exact nested JSON schema (key names, nesting depth)
- New directory layout specifics (exact folder names and groupings)
- Which KMS-compatible display control tool to use if vcgencmd needs replacing
- MQTT discovery payload structure
- Auto-restart script implementation details
- Bootstrap prompting UX

</decisions>

<specifics>
## Specific Ideas

- Display control is confirmed working today — don't break what works, just ensure status reporting is truthful
- User values being able to flip between dev branch and main on the Pi hardware for testing — this is the primary testing workflow
- "Positive confirmation is better than implying a command worked" — status should be source of truth from hardware
- Current production (main) has completely different structure and no centralized config — branches will diverge significantly during Phase 1

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-centralized-configuration-core-fixes*
*Context gathered: 2026-02-11*
