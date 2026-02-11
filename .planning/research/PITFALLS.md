# Pitfalls Research

**Domain:** Raspberry Pi Kiosk Dashboard Hardening
**Researched:** 2026-02-11
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: vcgencmd Display Control Broken by KMS Driver

**What goes wrong:**
The `vcgencmd display_power` command silently fails when using the modern vc4-kms-v3d driver (default in Raspberry Pi OS Bullseye+). The display may briefly turn off then immediately power back on, or the command has no effect at all.

**Why it happens:**
Raspberry Pi OS Bullseye moved display control from firmware to the Linux kernel via vc4-kms-v3d. vcgencmd only works when firmware drives the display pipeline. Developers copy old tutorials using vcgencmd without realizing driver changes make it obsolete.

**How to avoid:**
- Use `wlopm` for Wayland-based display control (modern approach)
- Use `xset dpms force off/on` for X11-based display control
- Check `/boot/config.txt` for `dtoverlay=vc4-kms-v3d` to confirm driver in use
- Never rely on vcgencmd for production display control on modern Pi OS

**Warning signs:**
- Display control works intermittently
- vcgencmd command returns success but display doesn't respond
- Kernel update suddenly breaks working display control
- Display turns off then immediately back on

**Phase to address:**
Phase 1 (Display Control) - Verify wlopm works correctly, add fallback detection for driver type

---

### Pitfall 2: MQTT Reconnection Threading Deadlock

**What goes wrong:**
After 12-24 hours of operation, the MQTT listener stops processing messages despite appearing to run. WiFi remains connected, service shows "active", but commands are ignored. Systemd shows no errors.

**Why it happens:**
paho-mqtt's threading model is fragile. Threads can lose connection to the main program scope while still appearing to run. The event loop continues, log messages print, but callbacks don't fire. Keepalive packets may continue sending, masking the deadlock.

**How to avoid:**
- Use `loop_forever()` in main thread, not `loop_start()` with manual sleep loop
- Implement connection heartbeat that publishes to a test topic every 60-120 seconds
- Add external monitoring that verifies message processing, not just process existence
- Use `clean_session=False` and QoS 1 for critical messages to survive reconnects
- Set reconnect_delay_set() to exponential backoff (1, 2, 4, 8... up to 120 seconds)

**Warning signs:**
- MQTT status shows "online" but commands don't execute
- Last log message is hours/days old but service is "active"
- Restarting service immediately fixes the issue
- Problem occurs only after long uptime (8+ hours)

**Phase to address:**
Phase 2 (MQTT Reliability) - Add heartbeat publishing, external health check, systemd watchdog integration

---

### Pitfall 3: systemd Service Dependency Race Conditions

**What goes wrong:**
Service starts before network is fully ready, or before graphical environment is available. Service appears to start correctly but core functionality fails. Common with `After=network.target` which only waits for network subsystem initialization, not actual connectivity.

**Why it happens:**
- `network.target` != network connectivity (just means network daemon started)
- `graphical.target` fires before X11/Wayland fully initializes
- Changing service definition after enabling it leaves stale symlinks in `/etc/systemd/system/*.target.wants`
- Dependencies must be in BOTH `After=` (ordering) and `Requires=`/`Wants=` (dependency)

**How to avoid:**
- Use `After=network-online.target` + `Wants=network-online.target` for network-dependent services
- For GUI services, use `After=graphical.target` + explicit 10-15 second `ExecStartPre=/bin/sleep 15`
- Always run `systemctl daemon-reload` after editing service files
- Disable service before editing, re-enable after: `systemctl disable foo && systemctl enable foo`
- Test with cold boot (power cycle), not just `systemctl restart`

**Warning signs:**
- Service works when started manually but fails on boot
- Adding sleep to service fixes the issue
- Changing service file has no effect after reboot
- journalctl shows service started before dependencies

**Phase to address:**
Phase 3 (Service Hardening) - Audit all service dependencies, add explicit wait times, document cold boot testing

---

### Pitfall 4: --disable-web-security Creates Attack Vector

**What goes wrong:**
The `--disable-web-security` Chromium flag bypasses Same-Origin Policy, CORS, and other critical browser security features. Any malicious JavaScript in the dashboard can make requests to other services on the local network, steal data from other tabs, or execute arbitrary code in other origins.

**Why it happens:**
Developers copy kiosk tutorials that include this flag to work around CORS issues during development. The flag gets committed to production without understanding the security implications. It's often cargo-culted alongside other Chromium flags.

**How to avoid:**
- Remove `--disable-web-security` immediately - it's almost never needed
- If CORS issues exist, fix them on the server side (proper Access-Control-Allow-Origin headers)
- Use `--user-data-dir` for session isolation without security bypass
- For local HTML files, use a local web server instead of file:// URLs
- Document why each Chromium flag is needed

**Warning signs:**
- Flag present in kiosk.sh without documented justification
- CORS errors in browser console (sign you need server-side fix, not security bypass)
- Dashboard loads local files via file:// protocol
- Multiple data directories or profile flags combined with security flags

**Phase to address:**
Phase 1 (Chromium Hardening) - Remove flag, test for breakage, fix CORS properly if needed

---

### Pitfall 5: Network Watchdog Creates Infinite Reboot Loop

**What goes wrong:**
Watchdog script detects network loss and triggers reboot. System reboots before network interface fully initializes. Watchdog detects "network down" during boot, triggers another reboot. System enters infinite reboot loop with 2-5 minute cycles.

**Why it happens:**
- Watchdog runs too early in boot sequence (before network.target stabilizes)
- Watchdog timeout too short for WiFi authentication and DHCP
- No "already rebooted" flag protection (unlike touchscreen-check.sh)
- DNS check fails due to resolver not ready, not actual network failure
- IPv6 prefix changes confuse dhcpcd, causing high DNS query volume

**How to avoid:**
- Use systemd timer (not cron) with `After=network-online.target`
- Wait minimum 90-120 seconds after boot before first network check
- Use flag file in `/var/run/` to prevent successive reboots within N minutes
- Check multiple network indicators: ping gateway, ping DNS, DNS resolution, HTTP request
- Restart network service first, only reboot if restart fails
- Configure dhcpcd with `noipv6rs` or `inform6` if IPv6 causes issues

**Warning signs:**
- System reboots during boot process
- Watchdog log shows "network down" less than 120 seconds after boot
- Multiple reboots with exactly the same timing pattern
- dhcpcd logs show constant IPv6 address changes
- eth0/wlan0 shows "up down up down" rapid cycling in logs

**Phase to address:**
Phase 2 (Network Watchdog) - Implement staged network recovery, flag-based loop protection, multi-check validation

---

### Pitfall 6: Chromium Touch Flags Break Mouse Input

**What goes wrong:**
Attempting to fix touch input issues by adding flags like `--touch-events=enabled` or `--force-device-scale-factor` breaks mouse input. Cursor becomes offset, clicks don't register correctly, or pointer events stop working entirely.

**Why it happens:**
Chromium on Raspberry Pi auto-detects touchscreen vs. mouse. Manual override flags conflict with auto-detection. Some flags are for Android/ChromeOS and don't work on Linux. Flag combinations have undocumented interactions.

**How to avoid:**
- Let Chromium auto-detect input devices - don't override with flags
- Use `unclutter` for cursor hiding, not Chromium flags
- If touch isn't working, fix at OS level (check evdev, X11 input configuration), not Chromium
- Test with both touch and mouse after any flag changes
- Document which flags are for debugging vs. production

**Warning signs:**
- Touch works but mouse doesn't (or vice versa)
- Cursor position offset from actual click location
- Adding touch-related flags changes mouse behavior
- Input works when Chromium started manually but fails in kiosk mode

**Phase to address:**
Phase 1 (Input Validation) - Remove experimental input flags, verify both input methods work

---

### Pitfall 7: Filesystem Corruption from Power Loss

**What goes wrong:**
Unexpected power loss corrupts systemd journal, causes boot failures, or breaks MQTT configuration files. System enters degraded state requiring SD card recovery or reflash.

**Why it happens:**
SD cards are vulnerable to corruption during active writes. systemd journal writes constantly. Config files may be partially written during power loss. Raspberry Pi 3B/4 models more susceptible than Pi 1/2 due to journaling behavior.

**How to avoid:**
- Use overlay filesystem for read-only root (OverlayFS via raspi-config)
- Mount `/var/log` to tmpfs to prevent journal corruption: `tmpfs /var/log tmpfs defaults,noatime,mode=0755 0 0`
- Write critical configs to `/boot` (FAT32 more resilient than ext4 to corruption)
- Implement graceful shutdown via MQTT command before power-off
- Use systemd's `RuntimeMaxSec=` to periodically restart services, flushing buffers
- Enable journald rate limiting: `RateLimitBurst=1000` in `/etc/systemd/journald.conf`

**Warning signs:**
- Boot hangs at "A start job is running for..."
- journalctl shows "Journal file corrupted"
- Config files contain partial data or null bytes
- System requires fsck on boot
- Services fail to start after power cycle but work after clean reboot

**Phase to address:**
Phase 3 (Filesystem Hardening) - Implement overlay FS, tmpfs logging, graceful shutdown MQTT command

---

### Pitfall 8: Project Path Restructuring Breaks Services

**What goes wrong:**
Moving project directory, renaming scripts, or reorganizing file structure silently breaks systemd services and autostart entries. Services fail to start after boot, showing "File not found" errors buried in journalctl.

**Why it happens:**
- Systemd service files use absolute paths rendered from `__REPO_ROOT__` token
- Autostart desktop files reference scripts by absolute path
- Bootstrap script renders paths at provisioning time, not dynamically
- Changing paths requires re-running bootstrap or manually editing multiple files
- Symlinks can mask the issue temporarily then break on reboot

**How to avoid:**
- Use `__REPO_ROOT__` template tokens in all config files, never hardcode paths
- Document which files contain rendered paths in CLAUDE.md
- Add `verify.sh` check that validates all paths exist and are executable
- After restructuring, grep entire project for old paths: `git grep "/old/path"`
- Re-run bootstrap.sh after moving project directory
- Consider using systemd's `%h` (home dir) instead of absolute paths where possible

**Warning signs:**
- Service works in development but fails after git pull
- `systemctl status` shows "No such file or directory"
- `verify.sh` fails after restructuring
- Scripts execute manually but fail via systemd
- Autostart works for developer but fails on fresh Pi setup

**Phase to address:**
Phase 4 (Configuration Management) - Implement path validation in verify.sh, document path dependencies, add pre-commit hook to detect hardcoded paths

---

### Pitfall 9: MQTT Status Reporting Lies to Home Assistant

**What goes wrong:**
MQTT listener publishes "on" status when it receives "on" command, but display control script actually fails. Home Assistant shows display is "on" when it's actually off. Automation loops: HA thinks display is on, tries to turn it off, MQTT publishes "off", but display was already off so nothing changes.

**Why it happens:**
Current mqtt_listener.py assumes display_control.py command success means display changed state. It publishes status immediately after running command, before verifying actual display state. Status reporting in display_control.py is stubbed out ("Status check not implemented yet").

**How to avoid:**
- Implement real status checking in display_control.py using `wlopm` query
- MQTT listener should query actual state after every command, not echo command
- Publish "unknown" status if display_control.py returns non-zero exit code
- On reconnect, always query and publish actual state, don't assume previous state
- Use MQTT retained messages so HA gets last known state on restart

**Warning signs:**
- HA dashboard shows wrong display state
- Sending same command twice has different effects
- Display state in HA doesn't match physical display
- MQTT listener restart causes HA to show "unknown" briefly then wrong state
- Automation triggers but display doesn't change

**Phase to address:**
Phase 1 (MQTT Status Fix) - Implement wlopm status query, actual state verification before publishing

---

### Pitfall 10: Hardware Mocking Tests Pass Locally But Fail on Pi

**What goes wrong:**
Tests using `Mock.GPIO` or `fake-rpi` pass 100% on Windows development laptop. Deployed to Pi, actual GPIO/touchscreen interactions fail. Tests give false confidence.

**Why it happens:**
Mock libraries simulate API shape but not actual hardware timing, failure modes, or edge cases. GPIO pins have electrical characteristics mocks don't capture. Touchscreen USB enumeration timing can't be mocked. Tests validate "code runs" not "hardware works."

**How to avoid:**
- Separate unit tests (mock hardware) from integration tests (real hardware)
- Mark integration tests with `@pytest.mark.hardware` decorator
- Run integration tests in CI on actual Pi hardware, not in GitHub Actions
- Document in README which tests require hardware
- Use environment variable `RPI_HARDWARE_AVAILABLE` to skip integration tests on dev laptop
- Test failure modes: unplug touchscreen, simulate WiFi drop, kill MQTT broker
- Add smoke tests that run on actual Pi after deployment

**Warning signs:**
- 100% test pass rate on laptop, failures on Pi
- Tests don't catch touchscreen timing issues
- GPIO tests pass but physical GPIO circuits don't work
- No way to run tests on actual hardware in CI
- Tests mock external services (MQTT broker) without integration tests

**Phase to address:**
Phase 4 (Testing Infrastructure) - Implement hardware vs. mock test separation, document integration test requirements, add post-deploy smoke tests

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Using `--disable-web-security` | Bypasses CORS during dev | Critical security hole, network attack vector | Never in production |
| Hardcoding paths instead of `__REPO_ROOT__` | Faster to write | Breaks on path changes, unreproducible setup | Never |
| `loop_start()` + manual sleep instead of `loop_forever()` | Feels more "controllable" | Threading deadlocks after 12+ hours | Never for production MQTT |
| `After=network.target` instead of `network-online.target` | Starts faster | Random failures on boot | Only if service has retry logic |
| Skipping integration tests on real hardware | Faster CI | False confidence, production failures | Only in MVP, must fix by Phase 4 |
| tmpfs for `/var/log` | Prevents corruption | Loses all logs on reboot | Acceptable with remote log forwarding |
| Overlay FS for root | Maximum corruption protection | Difficult to debug, manual writeable mode required | Production kiosks, not dev setups |
| Auto-login to Pi user | Easy unattended boot | Anyone with physical access has full control | Acceptable for home kiosk, not public |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Home Assistant MQTT | Using QoS 0, no retained messages | QoS 1 + retained for state topics, LWT for availability |
| Chromium + Touchscreen | Adding input flags to "fix" touch | Let Chromium auto-detect, fix OS-level evdev if broken |
| systemd + MQTT | `Restart=always` without exponential backoff | Use `RestartSec=10` + connection backoff in code |
| wlopm + display control | Running as root in systemd | Run as user, set `XDG_RUNTIME_DIR` environment var |
| WiFi + watchdog | Checking only ping, not DNS/HTTP | Multi-stage validation: gateway ping → DNS ping → DNS resolve → HTTP GET |
| Chromium + auto-login | Password prompts on boot | `--password-store=basic` flag required |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| systemd journal unbounded growth | SD card fills up, system unbootable | `SystemMaxUse=100M` in journald.conf, or tmpfs mount | After 2-3 months continuous uptime |
| Chromium memory leak | OOM kills after days/weeks | systemd `RestartSec=24h` to cycle Chromium daily | 7-14 days uptime on 1GB Pi models |
| MQTT message queue buildup | Listener becomes unresponsive | Set `max_queued_messages` limit in paho-mqtt | When network drop lasts > 5 minutes |
| Unclutter CPU usage | 100% CPU on one core | Use `-idle 0.5` not `-idle 0.1` (lower = more CPU) | Always, just less noticeable on Pi 4 |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| `--disable-web-security` in Chromium | JavaScript can access local network, steal tokens from other tabs | Remove flag, fix CORS server-side |
| Auto-login to Pi user + sudo without password | Physical access = full system control | Create dedicated kiosk user with limited permissions |
| Hardcoded MQTT credentials in git | Credentials leaked in commit history | Use `config/mqtt.json` (gitignored) + template pattern |
| SSH enabled with default password | Remote access for attackers | Change default password, use key-based auth, or disable SSH in production |
| HTTP dashboard URL not HTTPS | Credentials/data visible on WiFi | Use HTTPS, set up local CA if needed |
| Running MQTT listener as root | Exploit in listener = root compromise | Run as dedicated user (current setup correct) |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No visual feedback during boot | User thinks Pi is broken, unplugs during boot | Add boot splash screen or LED status indicator |
| Display turns off mid-interaction | User frustrated, thinks system crashed | Implement activity detection before MQTT power-off |
| Chromium crash leaves blank screen | System appears broken until reboot | systemd `Restart=always` + crash detection |
| On-screen keyboard covers input fields | Can't see what you're typing | Size/position keyboard with `onboard --size=800x300` at bottom |
| No "connecting to network" indicator | Silent failures look like system hangs | Add Chromium flag `--disable-offline-mode` to show connection status |
| Mouse cursor visible on touchscreen | Looks unpolished, confusing to touch | Use `unclutter -idle 0.5` |

## "Looks Done But Isn't" Checklist

- [ ] **MQTT Control:** Often missing actual status verification — verify display_control.py status command works and MQTT publishes real state
- [ ] **Network Watchdog:** Often missing boot loop protection — verify flag file exists and prevents infinite reboots
- [ ] **Display Control:** Often using vcgencmd (broken on modern Pi OS) — verify wlopm works with vc4-kms-v3d driver
- [ ] **systemd Dependencies:** Often missing network-online.target — verify services wait for actual network, not just network subsystem
- [ ] **Chromium Security:** Often includes `--disable-web-security` — verify flag is removed or justified in comments
- [ ] **MQTT Reconnection:** Often missing thread deadlock protection — verify heartbeat publishing and external health checks exist
- [ ] **Path Dependencies:** Often hardcoded paths — verify all configs use `__REPO_ROOT__` tokens and verify.sh validates paths
- [ ] **Filesystem Corruption:** Often no power-loss protection — verify overlay FS or tmpfs logging, or document as known risk
- [ ] **Integration Tests:** Often only unit tests with mocks — verify hardware integration tests exist and run on actual Pi
- [ ] **Service Restart Logic:** Often `Restart=always` without backoff — verify RestartSec delays and connection backoff in code

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| vcgencmd broken by driver | LOW | Switch to wlopm, update display_control.py, test on/off/status |
| MQTT threading deadlock | LOW | Add external healthcheck, implement heartbeat, or use systemd watchdog |
| systemd dependency race | LOW | Update After=/Wants= directives, daemon-reload, test cold boot |
| `--disable-web-security` | MEDIUM | Remove flag, test dashboard, fix CORS if needed, redeploy |
| Network watchdog loop | MEDIUM | SSH during boot window, disable watchdog service, fix logic, re-enable |
| Touch flags break mouse | LOW | Remove touch flags from kiosk.sh, restart, test both inputs |
| Filesystem corruption | HIGH | Reflash SD card, restore configs from git, re-run bootstrap.sh |
| Path restructuring breaks services | MEDIUM | Re-run bootstrap.sh, or manually update paths in systemd files + daemon-reload |
| MQTT status lies | LOW | Implement status query, update publishing logic, restart mqtt-listener |
| Mock tests mask hardware bugs | MEDIUM | Add integration tests, run on Pi hardware, document hardware requirements |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| vcgencmd broken by KMS | Phase 1: Display Control | Run display_control.py on/off/status, verify with physical display |
| MQTT threading deadlock | Phase 2: MQTT Reliability | Let run 48+ hours, verify heartbeat in logs, test message processing |
| systemd dependency race | Phase 3: Service Hardening | Cold boot test (power cycle) 5 times, check journalctl for failures |
| --disable-web-security | Phase 1: Chromium Hardening | Remove flag, test dashboard loads, grep code for CORS errors |
| Network watchdog loop | Phase 2: Network Watchdog | Simulate network drop, verify staged recovery, check flag file prevents loop |
| Touch flags break mouse | Phase 1: Input Validation | Test both touchscreen and USB mouse interactions |
| Filesystem corruption | Phase 3: Filesystem Hardening | Power cycle during write operation, verify no corruption |
| Path restructuring | Phase 4: Config Management | Move project dir, run verify.sh, check services start correctly |
| MQTT status lies | Phase 1: MQTT Status Fix | Send command, verify HA state matches physical display |
| Mock test false confidence | Phase 4: Testing Infrastructure | Run integration tests on actual Pi, verify hardware-dependent tests fail correctly when hardware missing |

## Phase-Specific Warnings

### Phase 1: Core Functionality Fixes
- Don't add new features, only fix existing broken functionality
- Verify each fix on actual Pi hardware before committing
- Document why --disable-web-security exists before removing (may reveal CORS issues)
- Test display control cold boot and after 24h uptime

### Phase 2: Reliability & Resilience
- Network watchdog must include boot loop protection (study touchscreen-check.sh pattern)
- MQTT reliability requires external healthcheck, not just internal connection status
- Don't assume network.target means network is usable
- Test all watchdogs in failure scenarios, not just success paths

### Phase 3: Hardening & Polish
- Filesystem hardening makes debugging harder (overlay FS, tmpfs logs)
- Implement graceful shutdown MQTT command before overlay FS
- systemd watchdog integration requires careful tuning to avoid false-positive reboots
- Power-loss testing requires actual power cuts, not `systemctl reboot`

### Phase 4: Code Quality & Testing
- Integration tests will require actual Pi hardware in CI or manual testing protocol
- Path refactoring requires coordination with verify.sh updates
- Don't restructure paths without re-running bootstrap and testing on clean Pi
- Tests that pass 100% on laptop but fail on Pi indicate mocking is too permissive

## Known Constraints

### MUST NOT CHANGE
- **Touchscreen cold→soft reboot pattern**: The touchscreen-check.sh service with flag-based protection is battle-tested and MUST remain unchanged. Any network watchdog or other auto-reboot logic must respect this pattern.

### REQUIRES HARDWARE VALIDATION
- Display power control (wlopm)
- Touchscreen input detection
- GPIO interactions (if added)
- Network watchdog recovery
- Cold boot behavior
- Power-loss filesystem corruption testing

### DEVELOPMENT ENVIRONMENT LIMITATIONS
- Windows laptop cannot run integration tests requiring Linux kernel features (GPIO, systemd, evdev)
- Mock libraries (Mock.GPIO, fake-rpi) provide API compatibility but not behavior parity
- MQTT broker can be mocked for unit tests but requires real broker for integration tests
- Chromium kiosk mode cannot be fully tested on Windows

## Sources

### WiFi & Network Management
- [Network watchdog? - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=390584)
- [Keep Your Raspberry Pi Online: Fixing WiFi Drops and SSH Disconnects - DevGuide.dev](https://devguide.dev/blog/raspberry-pi-stays-online)
- [NetworkManager ipv6 dhcp bogus leases - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=389743)
- [dhcpcd hangs - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=237670)

### Display Control & HDMI
- [HDMI power on/off problems - vcgencmd broken with kernel update - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=347425)
- [RPi4B does not support vcgencmd display_power 0 · Issue #1224](https://github.com/raspberrypi/firmware/issues/1224)
- [Screenly - How to automatically turn off and on your monitor](https://www.screenly.io/blog/2017/07/02/how-to-automatically-turn-off-and-on-your-monitor-from-your-raspberry-pi/)

### Chromium Kiosk Mode
- [Chromium in Kiosk mode: Interaction via touch display sometimes not possible - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=364840)
- [How to run Chromium in kiosk mode on a Raspberry Pi 2025 · GitHub](https://gist.github.com/lellky/673d84260dfa26fa9b57287e0f67d09e)
- [How to use a Raspberry Pi in kiosk mode - Raspberry Pi](https://www.raspberrypi.com/tutorials/how-to-use-a-raspberry-pi-in-kiosk-mode/)
- [Raspberry Pi Chromium Kiosk Autostart: Complete Setup Guide & 2026 Best Practices](https://copyprogramming.com/howto/raspberry-pi-4-autostart-chromium)

### systemd Service Management
- [systemd service for start at boot - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=335441)
- [starting systemd service after GUI is up - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?p=2358868)
- [any chance to fix dependency ordering cycle of systemd? - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=125856)
- [The ultimate guide on using systemd to autostart scripts - TheDigitalPictureFrame.com](https://www.thedigitalpictureframe.com/ultimate-guide-systemd-autostart-scripts-raspberry-pi/)

### MQTT Reliability
- [MQTT losing connection after many hours - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=311553)
- [MQTT Python Paho disconnection BUG - Raspberry Pi Forums](https://www.raspberrypi.org/forums/viewtopic.php?t=175813)
- [Paho MQTT client not reconnecting - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=328619)
- [[SOLVED] MQTT/Internet reconnection after loss not working - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=356965)

### Testing & Hardware Mocking
- [Testing | gpiozero/gpiozero | DeepWiki](https://deepwiki.com/gpiozero/gpiozero/6.1-testing)
- [How to test Python applications running on Raspberry Pi with pytest - woteq Softwares](https://woteq.com/how-to-test-python-applications-running-on-raspberry-pi-with-pytest/)
- [fake-rpi · PyPI](https://pypi.org/project/fake-rpi/)
- [GitHub - codenio/Mock.GPIO: Mock Library for RPI.GPIO](https://github.com/codenio/Mock.GPIO)

### Filesystem Corruption & Power Loss
- [Is the overlay filesystem required to prevent corruption on power loss? - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=361461)
- [systemd journal corruption - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=349555)
- [How to prevent corruption upon power loss? - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=291792)
- [Systematic journal corruption on clean install of Raspian Lite Bookworm 64bit - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=366591)

### Bootloader & Recovery
- [Raspberry Pi 4/400 Bootloader Firmware Recovery Guide - Fastoe](https://www.fastoe.com/blog/rpi-4_400-eeprom-recovery-guide)
- [Raspberry Pi 4/400 EEPROM Firmware Update/Recovery Guide](https://jamesachambers.com/raspberry-pi-4-bootloader-firmware-updating-recovery-guide/)
- [Update Raspberry Pi Bootloader - bret.dk](https://bret.dk/update-raspberry-pi-bootloader/)

### Security
- [[Solved] How to Setup Chromium Kiosk Mode in Raspberry Pi?](https://www.airdroid.com/mdm/chromium-kiosk-mode/)
- [Disable Auto-login in Raspberry Pi OS - Raspberry Pi Spy](https://www.raspberrypi-spy.co.uk/2022/02/disable-auto-login-in-raspberry-pi-os/)

---
*Pitfalls research for: Raspberry Pi Kiosk Dashboard Hardening*
*Researched: 2026-02-11*
