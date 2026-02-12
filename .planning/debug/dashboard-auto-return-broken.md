---
status: verifying
trigger: "dashboard-auto-return-broken - After navigating away from default HA dashboard via sidebar, browser never auto-returns even after idle timeout expires"
created: 2026-02-11T00:00:00Z
updated: 2026-02-11T00:03:00Z
---

## Current Focus

hypothesis: CONFIRMED - F5 reload cannot return to dashboard because it reloads the current URL, not the original dashboard URL
test: Fix implemented - replaced F5 with CDP Page.navigate, need hardware verification on Pi
expecting: After idle timeout, browser navigates back to configured dashboard URL regardless of current page
next_action: User deploys to Pi, installs python3-websocket, updates config.json, and tests

## Symptoms

expected: After the configured idle timeout, the kiosk browser should automatically navigate back to the default HA dashboard
actual: The browser stays on whatever page was navigated to via HA sidebar - it never returns to the default dashboard
errors: Not yet checked - need to examine journalctl and relevant logs
reproduction: Navigate away from the default dashboard using HA sidebar navigation, wait past the timeout
started: Has been happening since the feature was implemented - never observed working

## Eliminated

## Evidence

- timestamp: 2026-02-11T00:00:30Z
  checked: watchdog/browser-watchdog.sh line 49
  found: Auto-return mechanism is `DISPLAY=:0 xdotool key F5` - a simple page refresh
  implication: F5 reloads the current page at its current URL. If the user navigated to a different HA page via sidebar, the URL changes and F5 just reloads THAT page.

- timestamp: 2026-02-11T00:00:30Z
  checked: 02-RESEARCH.md Open Question #2
  found: Research document explicitly identified this risk and recommended URL navigation as preferred approach
  implication: Known risk that materialized. Plan 02-02 included a fallback path for this scenario.

- timestamp: 2026-02-11T00:00:30Z
  checked: kiosk/kiosk.sh line 57-73
  found: Chromium launched with --kiosk flag which hides the address bar
  implication: ctrl+l approach won't work. CDP (Chrome DevTools Protocol) via --remote-debugging-port is the solution.

- timestamp: 2026-02-11T00:01:30Z
  checked: Web research on CDP navigation approaches
  found: --remote-debugging-port=9222 exposes HTTP/WebSocket API. Page.navigate command navigates to any URL. python3-websocket package available via apt on Debian Bookworm.
  implication: Clean solution: add --remote-debugging-port to Chromium, create Python helper for CDP navigation.

- timestamp: 2026-02-11T00:02:30Z
  checked: All bash scripts pass `bash -n` syntax check, Python script passes py_compile
  found: No syntax errors in any modified files
  implication: Code is ready for deployment and hardware testing

## Resolution

root_cause: The browser watchdog uses F5 (page refresh) to "return" to the default dashboard, but F5 only reloads the current page at its current URL. When the user navigates to a different HA page via sidebar, the browser URL changes (HA is a SPA that updates the URL path). F5 just refreshes that navigated-to page - it never navigates back to the configured dashboard URL. This was a known risk documented in 02-RESEARCH.md Open Question #2 that materialized as expected.

fix: Replaced F5 reload with Chrome DevTools Protocol (CDP) navigation via --remote-debugging-port=9222. Created lib/browser_control.py helper that uses Page.navigate to navigate the browser to any URL. The browser watchdog now calls this helper instead of sending F5. Falls back to F5 if CDP is unavailable. Also dropped inactivity timeout default from 600s to 60s for testing.

verification: All scripts pass syntax checks (bash -n, py_compile). Needs hardware verification on Pi - user must deploy, install python3-websocket, update config.json, and test.

files_changed:
  - kiosk/kiosk.sh (added --remote-debugging-port=9222 to Chromium launch)
  - watchdog/browser-watchdog.sh (replaced F5 with CDP navigation via navigate_to_dashboard function)
  - lib/browser_control.py (NEW - CDP navigation helper using websocket-client)
  - config.json.template (inactivity_timeout_seconds 600 -> 60 for testing)
  - setup/bootstrap.sh (added python3-websocket to apt packages, chmod for browser_control.py, updated default timeout in config generation)
