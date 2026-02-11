# Codebase Concerns

**Analysis Date:** 2026-02-11

## Security Considerations

**Chromium Web Security Disabled:**
- Issue: `scripts/kiosk.sh` line 26 uses `--disable-web-security` flag to allow display of dashboard without HTTPS
- Files: `scripts/kiosk.sh`
- Risk: Disables CORS protections, cross-site scripting mitigations, and other security features. Any malicious actor with network access can inject content into the dashboard.
- Current mitigation: Private network (assumed), but no authentication on kiosk entrypoint
- Recommendations:
  - Enable HTTPS on Home Assistant dashboard with valid certificates instead of disabling security
  - Restrict network access to kiosk Pi via firewall rules
  - Document security assumptions in setup guide
  - Consider using `--no-sandbox` instead of `--disable-web-security` if running in confined environment

**Hardcoded Dashboard URL:**
- Issue: Dashboard URL `http://192.168.68.75:8123` is hardcoded in `scripts/kiosk.sh` line 35
- Files: `scripts/kiosk.sh`
- Risk: If Home Assistant IP changes, kiosk breaks. Requires code modification and redeploy. Not user-configurable during bootstrap.
- Fix approach:
  - Move URL to `config/kiosk.config` template (rendered during bootstrap like MQTT config)
  - Prompt user during `bootstrap.sh` for dashboard URL
  - Use template token approach: `__DASHBOARD_URL__` in template, render during setup

**MQTT Credentials in Plaintext:**
- Issue: `config/mqtt.json` stores username/password in plaintext JSON file
- Files: `config/mqtt.json`, `scripts/mqtt_listener.py` lines 210-212
- Risk: Anyone with file access can read credentials. Permissions set to 600 but file is readable by user process.
- Current mitigation: `.gitignore` prevents commit, `bootstrap.sh` line 154 sets 600 permissions
- Recommendations:
  - Consider using environment variables instead of JSON file (sourced from secure location)
  - Document need for strict Pi access control
  - Consider Home Assistant service account tokens instead of user credentials for MQTT

**Display URL Exposure:**
- Issue: Home Assistant dashboard URL visible in `readme.md` line 179 as example (192.168.1.220:8123)
- Files: `readme.md`
- Risk: Example exposes internal network topology. Users copy-paste and may leave personal IPs in documentation.
- Fix approach: Use placeholder like `<HOME_ASSISTANT_IP>:8123` instead of concrete IP

## Known Issues

**Display Status Command Not Implemented:**
- Symptoms: `display_control.py status` command returns placeholder message, not actual display power state
- Files: `scripts/display_control.py` lines 31-33
- Trigger: Running `python3 scripts/display_control.py status` or Home Assistant requesting status via MQTT
- Impact: MQTT listener cannot reliably report display status to Home Assistant. Status will show as "unknown" after startup.
- Workaround: Home Assistant automations assume display state without verification. Manual refresh button available via ha-init.py button entity.
- Fix approach:
  - Implement proper status detection using `wlopm --print` or similar query method
  - Test on actual Wayland/wlopm setup to confirm detection method
  - Update mqtt_listener.py status parsing to handle real output format

**MQTT Listener Dependency Not Installed:**
- Symptoms: `mqtt_listener.py` fails to run if `paho-mqtt` not installed, but bootstrap doesn't install it
- Files: `scripts/setup/bootstrap.sh` line 117 - install_mqtt_dependencies function is commented out
- Trigger: First run of `mqtt-listener.service` after fresh bootstrap
- Impact: MQTT display control will fail silently. Service will keep restarting (Restart=always) but never succeed.
- Workaround: Manual `pip3 install paho-mqtt` required after bootstrap
- Fix approach: Uncomment line 117 in bootstrap.sh and verify pip3 is available before running install command

**Touchscreen Service Runs on Every Boot:**
- Symptoms: Service waits 60 seconds on every boot (including normal reboots), slowing startup
- Files: `scripts/touchscreen-check.sh` lines 18-20
- Impact: First 60 seconds after any reboot are blocked by hardware stabilization wait. Cold boots take additional 2-3 minutes due to automatic reboot.
- Current mitigation: Only one automatic reboot is performed (flag file prevents loops)
- Improvement path:
  - Detect boot type (cold vs warm reboot) and skip wait on warm boots
  - Use systemd conditional to skip service on non-cold-boot scenarios
  - Reduce wait time from 60 seconds if hardware stabilizes faster

## Test Coverage Gaps

**No Unit Tests for Display Control:**
- What's not tested: `scripts/display_control.py` command execution, wlopm subprocess handling, error conditions
- Files: `scripts/display_control.py`
- Risk: Breakage in display control goes undetected until manually tested on hardware
- Priority: Medium (hardware dependency makes testing difficult, but integration tests could mock wlopm)

**No Unit Tests for MQTT Listener:**
- What's not tested: Message parsing, command handling, status reporting, reconnection logic, signal handling
- Files: `scripts/mqtt_listener.py`
- Risk: MQTT connection issues, message format changes, or error handling breaks silently. Service restarts but may never connect.
- Priority: High (mission-critical for display control feature)
- Recommendation: Add mock-based tests with paho-mqtt.MQTTClient mocking

**No Integration Tests for Bootstrap:**
- What's not tested: Service file rendering, template substitution, systemd daemon-reload, permission setting
- Files: `scripts/setup/bootstrap.sh`
- Risk: Fresh Pi setup may fail silently (e.g., if sed rendering breaks path tokens). Only caught when deployed.
- Priority: High (critical path for setup)
- Recommendation: Run bootstrap in CI on test environment with mock systemd

**No Verification Tests for Kiosk Startup:**
- What's not tested: Chromium subprocess launch, window focusing, URL loading, display environment setup
- Files: `scripts/kiosk.sh`
- Risk: Kiosk may fail to launch on boot due to race conditions, display not ready, X11 environment issues
- Priority: Medium (caught on first power cycle but not in CI)

## Fragile Areas

**Hardcoded Paths in Bootstrap:**
- Files: `scripts/setup/bootstrap.sh` lines 82-85, `scripts/setup/verify.sh` lines 62-68
- Why fragile: Script assumes repo is at `~/dashboard-project`. Will fail silently if repo is cloned to different location.
- Safe modification: Use `$SCRIPT_DIR` and relative paths computed at runtime (already done correctly for config files, but explicit paths for script permissions are hardcoded)
- Test coverage: verify.sh tests this but doesn't report clearly when repo is in wrong location

**MQTT Listener Subprocess Timeout:**
- Files: `scripts/mqtt_listener.py` lines 134-139, 169-174
- Why fragile: 10-second timeout on `display_control.py` execution may be too short if wlopm is slow or system is under load
- Safe modification: Increase timeout to 30 seconds, add debug logging before/after subprocess calls
- Test coverage: No timeout testing - if wlopm takes 15 seconds, this breaks silently

**Touchscreen Detection by USB ID:**
- Files: `scripts/touchscreen-check.sh` line 8, 23
- Why fragile: Hardcoded ILITEK USB ID `222a:0001`. If touchscreen is replaced with different model, detection fails and triggers automatic reboot loop protection (max 1 reboot).
- Safe modification: Make USB ID configurable via environment variable or config file
- Test coverage: No test for detection logic - can only be verified on hardware

**Service Template Token Rendering:**
- Files: `scripts/setup/bootstrap.sh` lines 99-106, 170-176
- Why fragile: Uses `sed` to replace `__REPO_ROOT__` tokens. If repo path contains special sed characters (e.g., `/` or `&`), sed fails silently or produces malformed service files.
- Safe modification: Use sed `-e` with careful escaping, or switch to Python template rendering
- Test coverage: Only caught if repo path is unusual (e.g., contains spaces or special chars)

**MQTT Status Parsing:**
- Files: `scripts/mqtt_listener.py` lines 177-184
- Why fragile: Parses `display_control.py` stdout with loose string matching. Output format change breaks silently.
- Safe modification: Implement proper display_control.py status command first, then parse structured output (exit code or JSON)
- Test coverage: No output format tests

## Performance Bottlenecks

**60-Second Touchscreen Check Delay:**
- Problem: Every boot waits 60 seconds for hardware initialization before checking touchscreen
- Files: `scripts/touchscreen-check.sh` line 18
- Cause: Touchscreen USB controller doesn't enumerate reliably within first 60 seconds on cold boot
- Current capacity: Cold boot 2-3 minutes (60s wait + automatic reboot + 60s wait again), warm boot ~1-2 minutes (60s wait)
- Improvement path:
  - Test if 30-second wait is sufficient on current hardware
  - Implement exponential backoff detection (check at 10s, 20s, 30s, give up)
  - Use systemd OnBootSec with ExecStart condition to skip on non-cold-boots

**Chromium Startup Overhead:**
- Problem: Browser takes 10+ seconds to load after display environment setup
- Files: `scripts/kiosk.sh` lines 7, 21-35
- Cause: Full Chromium startup, profile initialization, page load
- Current capacity: Total startup time ~30-40 seconds from autostart trigger
- Improvement path:
  - Pre-warm browser cache with dashboard assets
  - Use persistent user-data-dir instead of /tmp to preserve cache across boots
  - Enable aggressive caching in Home Assistant dashboard

## Scaling Limits

**Single Dashboard Instance:**
- Current capacity: One Pi, one dashboard display
- Limit: Code is Pi-specific with hardcoded paths and usernames
- Scaling path: To add more dashboards, would need:
  - Configurable `User=` in systemd service template
  - Support for different home paths beyond `~/dashboard-project`
  - MQTT device identifiers parameterized to support multiple Pis

**MQTT Broker Availability:**
- Current capacity: Assumes single MQTT broker, no failover
- Limit: If Home Assistant/MQTT broker is down, display control unavailable (kiosk still runs)
- Scaling path:
  - Add fallback broker support to mqtt_listener.py
  - Implement MQTT connection retry with exponential backoff
  - Add circuit breaker pattern to handle persistent broker unavailability

## Dependencies at Risk

**Chromium Browser (apt package):**
- Risk: Heavy dependency, package may become unavailable or incompatible with Pi OS updates
- Impact: Kiosk fails to launch if chromium-browser package breaks or is removed
- Migration plan: Consider Epiphany (GNOME Web) as lightweight alternative, or Wayland-native browser if switching display servers

**wlopm Display Control Utility:**
- Risk: Wayland-specific tool, may not be available or may break with Wayland updates
- Impact: Display power control fails completely if wlopm is unavailable or changes output format
- Migration plan: Implement generic display control via HDMI CEC or GPIO relay control as fallback

**Paho MQTT Client Library:**
- Risk: Python package maintenance, API changes between versions
- Impact: MQTT listener fails if paho-mqtt updates incompatibly
- Current status: Not pinned to specific version in bootstrap
- Recommendations: Add `pip3 install paho-mqtt==2.1.1` (or latest stable) to bootstrap to ensure consistent version

**Python 3 Standard Library:**
- Risk: Code uses only stdlib (json, logging, subprocess, signal, pathlib), very low risk
- Impact: None identified - good practice of avoiding external dependencies

## Missing Critical Features

**Display Status Detection:**
- Problem: Cannot reliably query if display is on or off
- Blocks: Home Assistant cannot confirm command success, status always shows "unknown"
- Files: `scripts/display_control.py` line 32
- Impact: User automations cannot condition on display state
- Fix complexity: Medium (requires investigating wlopm query methods on actual hardware)

**Configuration Management for Dashboard URL:**
- Problem: Home Assistant URL hardcoded in kiosk.sh
- Blocks: Cannot change dashboard without editing script
- Impact: Reduces portability - repo must be customized per installation
- Fix complexity: Low (already using template approach for MQTT config, can apply same pattern)

**Error Recovery Mechanism:**
- Problem: If display control fails, MQTT listener logs error but takes no recovery action
- Blocks: Silent failures - Home Assistant thinks display is off when it's actually on
- Impact: Display state in Home Assistant becomes unreliable after any error
- Fix complexity: Medium (requires state machine to retry, reset on timeout, etc.)

**Chromium Crash Recovery:**
- Problem: If chromium-browser crashes, no automatic restart
- Blocks: Dashboard goes blank, requires manual SSH to restart
- Impact: Reduces reliability for unattended kiosk
- Fix complexity: Medium (can add watchdog service or use systemd restart policy)

## Security Audit Recommendations

1. **Immediate (High Priority):**
   - Replace `--disable-web-security` with proper HTTPS + certificate validation
   - Implement display status detection to close information gap
   - Install paho-mqtt dependency in bootstrap

2. **Short-term (Medium Priority):**
   - Parameterize hardcoded URLs and paths
   - Add environment variable support for sensitive config
   - Document network security requirements

3. **Long-term (Low Priority):**
   - Add comprehensive test suite for critical paths
   - Implement monitoring/alerting for service health
   - Consider running chromium in restricted environment (sandbox, unprivileged user)

---

*Concerns audit: 2026-02-11*
