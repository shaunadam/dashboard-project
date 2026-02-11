# Phase 2: Resilience & Watchdogs - Research

**Researched:** 2026-02-11
**Domain:** Network resilience, browser crash recovery, service coordination on Raspberry Pi 4 (X11/Bookworm)
**Confidence:** HIGH

## Summary

Phase 2 transforms the dashboard from a functional-when-everything-works kiosk into a production-hardened 24/7 system that recovers automatically from WiFi drops, browser crashes, and long-running drift. The existing codebase (from Phase 1) provides a solid foundation: centralized config.json with `cfg_get`/`cfg_require` (bash) and `get`/`require` (Python), systemd services for MQTT and touchscreen detection, and a proven flag-file boot-loop protection pattern in `touchscreen-check.sh`.

The primary technical domains are: (1) WiFi watchdog using `nmcli` (NetworkManager is default on Bookworm) with multi-stage network validation and flag-file reboot protection; (2) Chromium crash recovery via systemd service supervision with sed-based Preferences cleanup to suppress "restore pages" dialogs; (3) touch-drag scrolling via Chromium flags (`--disable-touch-drag-drop`, `--overscroll-history-navigation=0`) combined with CSS `user-select: none` injection; (4) inactivity auto-return using `xprintidle` + `xdotool` (confirmed X11 environment); (5) scheduled soft reboots via systemd timer; and (6) service coordination via systemd ordering directives.

The riskiest item is the WiFi watchdog -- an incorrect implementation can cause infinite reboot loops. The touchscreen-check.sh pattern (flag file in `/var/run/`, check flag before rebooting, clear on success) is the proven template to follow. The inactivity timeout has two viable approaches (xprintidle script vs. browser extension); the xprintidle approach is simpler and consistent with the project's X11-based architecture.

**Primary recommendation:** Build WiFi watchdog first (highest risk, needs most testing), then browser supervision, then touch/UX improvements, then scheduled reboot -- each as independently testable units.

## Standard Stack

### Core

| Tool/Library | Version | Purpose | Why Standard |
|-------------|---------|---------|--------------|
| nmcli (NetworkManager) | Bookworm default | WiFi connection management | Default on RPi OS Bookworm; replaces wpa_supplicant. Commands: `nmcli connection down/up`, `nmcli device wifi connect` |
| systemd timers | Built-in | Periodic watchdog execution, scheduled reboots | More reliable than cron for boot-time scheduling; integrates with service dependencies |
| xprintidle | apt package | Detect X11 user idle time in milliseconds | Lightweight, purpose-built for X11 idle detection; available as apt package |
| xdotool | Already installed | Simulate keyboard input for URL navigation | Already in project; used for browser automation on X11 |
| sed | Built-in | Modify Chromium Preferences file before launch | Standard tool for the well-known "exited_cleanly" fix |
| ping | Built-in | Network connectivity validation | Multi-stage: gateway ping, DNS ping (8.8.8.8), DNS resolution, HTTP check |
| curl | Already installed | HTTP endpoint validation for network check | Final stage of multi-stage network validation |

### Supporting

| Tool/Library | Version | Purpose | When to Use |
|-------------|---------|---------|-------------|
| logger | Built-in | Write to systemd journal from bash scripts | All watchdog scripts for consistent logging pattern |
| systemctl | Built-in | Service management, reboot | WiFi recovery (restart NetworkManager), scheduled reboot |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| xprintidle + xdotool (idle detection) | Chrome extension with chrome.idle API | Extension is more elegant but adds deployment complexity (extension management, --load-extension flag, manifest); xprintidle is simpler and consistent with existing X11 stack |
| systemd timer (scheduled reboot) | cron | cron works but systemd timers integrate with service ordering, boot-time awareness, and journal logging |
| nmcli (WiFi management) | wpa_supplicant direct | wpa_supplicant was deprecated on Bookworm; nmcli is the supported path forward |
| Separate watchdog scripts | Single monolithic watchdog | Separate scripts are independently testable, can be enabled/disabled individually, follow single-responsibility principle |

### Installation

```bash
# xprintidle is the only new package needed
sudo apt-get install -y xprintidle
```

All other tools (nmcli, systemd, xdotool, sed, ping, curl, logger) are already installed or built-in.

## Architecture Patterns

### Recommended Project Structure (New Files for Phase 2)

```
dashboard-project/
├── watchdog/
│   ├── wifi-watchdog.sh          # Network check + recovery logic (NET-01..NET-04)
│   └── browser-watchdog.sh       # Idle detection + auto-return (BRW-03)
├── kiosk/
│   └── kiosk.sh                  # MODIFIED: add touch flags, sed cleanup, systemd-managed
├── lib/
│   └── config.sh                 # EXISTING: used by all new bash scripts
├── setup/
│   ├── bootstrap.sh              # MODIFIED: add new services/timers
│   └── verify.sh                 # MODIFIED: add new service checks
└── config.json.template          # MODIFIED: config values already present from Phase 1
```

### Pattern 1: Flag-File Boot-Loop Protection (WiFi Watchdog)

**What:** Prevent infinite reboot loops by tracking whether a reboot has already been attempted.
**When to use:** Any watchdog that may trigger a reboot as a recovery action.
**Example:**

```bash
# Source: touchscreen-check.sh (existing proven pattern in this project)
FLAG_FILE="/var/run/wifi-reboot-attempted"

# Check if we already tried rebooting
if [ -f "$FLAG_FILE" ]; then
  log_message "ERROR: Reboot already attempted but network still down"
  log_message "Manual intervention required"
  exit 1
fi

# Set flag before rebooting
touch "$FLAG_FILE"
log_message "REBOOTING: Network recovery failed"
systemctl reboot
```

**Critical detail:** Flag files in `/var/run/` survive soft reboots but are cleared on power cycle (tmpfs). This is the exact behavior needed.

### Pattern 2: Multi-Stage Network Validation

**What:** Check multiple network indicators before declaring failure, preventing false positives.
**When to use:** WiFi watchdog to avoid unnecessary recovery actions.
**Example:**

```bash
# Stage 1: Ping default gateway (local network up?)
# Stage 2: Ping public DNS 8.8.8.8 (internet reachable?)
# Stage 3: DNS resolution test (DNS working?)
# Stage 4: HTTP GET to dashboard URL (actual service reachable?)

# Only if ALL stages fail should recovery be triggered.
# If gateway ping succeeds but DNS fails, restart NetworkManager (not reboot).
# If all fail, try nmcli down/up cycle first, then reboot as last resort.
```

### Pattern 3: Chromium Preferences Cleanup Before Launch

**What:** Modify Chromium's Preferences file to prevent "restore pages?" dialog after crash.
**When to use:** Every time Chromium starts (in kiosk launch script).
**Example:**

```bash
# Source: Raspberry Pi Forums, verified across multiple posts
CHROMIUM_PREFS="$USER_DATA_DIR/Default/Preferences"
if [ -f "$CHROMIUM_PREFS" ]; then
  sed -i 's/"exited_cleanly":false/"exited_cleanly":true/' "$CHROMIUM_PREFS"
  sed -i 's/"exit_type":"Crashed"/"exit_type":"Normal"/' "$CHROMIUM_PREFS"
fi
```

**Note:** The `--disable-session-crashed-bubble` flag alone is reportedly insufficient since Chromium v50+. The sed approach is the reliable fix confirmed across multiple community sources.

### Pattern 4: systemd Service for Kiosk Browser

**What:** Run Chromium under systemd supervision for automatic crash recovery.
**When to use:** Replace autostart-only approach with supervised service.
**Example:**

```ini
[Unit]
Description=Chromium Kiosk Browser
After=graphical.target network-online.target
Wants=graphical.target network-online.target

[Service]
Type=simple
User=shaun
Environment=DISPLAY=:0
ExecStartPre=/path/to/cleanup-preferences.sh
ExecStart=/path/to/kiosk/kiosk.sh
Restart=on-failure
RestartSec=5
StartLimitBurst=5
StartLimitIntervalSec=300

[Install]
WantedBy=graphical.target
```

**Important trade-off:** The current approach uses `~/.config/autostart/kiosk.desktop` which launches on desktop login. Moving to a systemd user service would provide automatic restart but requires careful integration with the X11 session. The simpler approach is to keep the autostart entry BUT wrap the kiosk script in a restart loop within the script itself, or add a separate browser-watchdog service that monitors and restarts Chromium.

### Pattern 5: Idle Detection with xprintidle

**What:** Monitor X11 idle time and navigate browser to home URL after timeout.
**When to use:** Auto-return to week planner page after configurable inactivity.
**Example:**

```bash
#!/bin/bash
# Browser watchdog: monitors idle time, navigates to home URL
IDLE_TIMEOUT_MS=$((INACTIVITY_TIMEOUT * 1000))  # Convert seconds to milliseconds

while true; do
  IDLE_MS=$(DISPLAY=:0 xprintidle)
  if [ "$IDLE_MS" -gt "$IDLE_TIMEOUT_MS" ]; then
    log_message "Idle timeout reached (${IDLE_MS}ms), returning to home page"
    DISPLAY=:0 xdotool key F5  # Reload page (returns to dashboard URL)
    sleep "$INACTIVITY_TIMEOUT"  # Wait full timeout before checking again
  fi
  sleep 10  # Check every 10 seconds
done
```

**Note:** `xdotool key F5` reloads the current page. For navigating to a specific URL, use `xdotool key ctrl+l` (focus address bar) then type URL and press Enter. However, since the kiosk always starts at the dashboard URL, a reload (F5) effectively returns to the home page since HA dashboards typically reset to their default view on reload.

### Pattern 6: WiFi Credential Application via nmcli

**What:** Authoritatively apply WiFi credentials from config.json, overwriting any manually-entered credentials.
**When to use:** WiFi watchdog recovery, ensuring the system always uses the configured SSID/password.
**Example:**

```bash
WIFI_SSID="$(cfg_require '.wifi.ssid')"
WIFI_PASSWORD="$(cfg_require '.wifi.password')"

# Check if connection profile exists
if nmcli -t -f NAME connection show | grep -q "^${WIFI_SSID}$"; then
  # Update existing connection with credentials from config
  sudo nmcli connection modify "$WIFI_SSID" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$WIFI_PASSWORD"
else
  # Create new connection profile
  sudo nmcli connection add type wifi con-name "$WIFI_SSID" \
    ifname wlan0 ssid "$WIFI_SSID"
  sudo nmcli connection modify "$WIFI_SSID" \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$WIFI_PASSWORD"
fi

# Bring connection up
sudo nmcli connection up "$WIFI_SSID"
```

### Anti-Patterns to Avoid

- **Watchdog triggers reboot without flag-file protection:** Will create infinite reboot loop if network takes time to initialize after boot. ALWAYS check for existing flag file first.
- **Using `network.target` instead of `network-online.target`:** network.target only means the network subsystem started, NOT that connectivity is available. WiFi may not be connected yet.
- **Checking network too soon after boot:** WiFi authentication + DHCP can take 30-60 seconds. Wait at least 120 seconds after boot before first network check.
- **Using `Restart=always` without rate limiting:** Without `StartLimitBurst` and `StartLimitIntervalSec`, a persistent failure creates a tight restart loop consuming system resources.
- **Relying only on `--disable-session-crashed-bubble`:** This flag is insufficient on modern Chromium. Must also modify the Preferences file with sed.
- **Using `loop_start()` in MQTT listener:** The existing mqtt_listener.py uses `loop_start()` with a manual sleep loop. This is a known pattern for threading deadlocks after 12-24h. The pitfall is documented but fixing it is a Phase 3/future concern -- Phase 2 should NOT change the MQTT listener architecture.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Network connectivity detection | Custom socket or HTTP library | `ping -c 1 -W 5` + `curl --max-time 5` | ping handles ICMP correctly, curl handles HTTP; both have proper timeout handling built in |
| WiFi credential management | Direct wpa_supplicant config editing | `nmcli connection modify/up` | nmcli is the supported interface on Bookworm; handles all edge cases of WPA negotiation |
| Idle time detection | Custom input event monitoring | `xprintidle` | xprintidle queries X server directly; handles all input devices transparently |
| Keyboard simulation | Custom X11 event injection | `xdotool` | Already installed; handles window focus, key simulation, timing correctly |
| Periodic execution | Custom sleep loops in bash | systemd timers | Timers survive service restarts, integrate with journal logging, respect boot ordering |
| Service restart logic | Custom PID-file monitoring | systemd Restart=on-failure | systemd handles all edge cases of process lifecycle, zombie cleanup, rate limiting |

**Key insight:** Every watchdog/monitoring task in Phase 2 has a purpose-built Linux tool or systemd feature. Custom implementations add complexity and miss edge cases that the standard tools handle.

## Common Pitfalls

### Pitfall 1: WiFi Watchdog Creates Infinite Reboot Loop

**What goes wrong:** Watchdog runs too early in boot sequence, detects "network down" before WiFi has time to authenticate, triggers reboot. Cycle repeats.
**Why it happens:** WiFi authentication + DHCP takes 30-60 seconds. `network-online.target` may fire before WiFi is fully connected on some configurations.
**How to avoid:**
- Use flag file in `/var/run/` (cleared on power cycle, survives soft reboot)
- Wait 120+ seconds after boot before first check (use `OnBootSec=2min` in timer)
- Staged recovery: nmcli down/up first, then NetworkManager restart, reboot only as last resort
- Check flag file BEFORE any recovery action
**Warning signs:** System reboots during boot, logs show "network down" < 120 seconds after boot, multiple reboots with identical timing

### Pitfall 2: Chromium "Restore Pages?" Dialog After Crash

**What goes wrong:** After crash or hard reboot, Chromium shows session restore prompt that blocks the dashboard.
**Why it happens:** Chromium writes crash state to Preferences file on abnormal exit. The `--disable-session-crashed-bubble` flag alone is unreliable on modern versions.
**How to avoid:**
- Run sed commands to set `exited_cleanly: true` and `exit_type: Normal` in Preferences BEFORE every Chromium launch
- Use `--user-data-dir` (already in kiosk.sh) to control the Preferences file location
- Add `--disable-session-crashed-bubble` AND `--disable-restore-session-state` as defense-in-depth
**Warning signs:** Dashboard shows restore dialog after reboot, family has to tap "Restore" or "X" to dismiss

### Pitfall 3: Touch-Drag Selects Text Instead of Scrolling

**What goes wrong:** Dragging finger on touchscreen highlights text instead of scrolling the page.
**Why it happens:** Chromium interprets touch-drag as text selection by default on non-mobile platforms. The HA dashboard CSS may not include `user-select: none`.
**How to avoid:**
- Add `--disable-touch-drag-drop` flag to Chromium launch (prevents drag-drop interpretation)
- Add `--overscroll-history-navigation=0` flag (prevents swipe-back/forward gesture)
- Add `--disable-pinch` flag (prevents accidental zoom)
- If CSS approach needed: inject `* { user-select: none; -webkit-user-select: none; }` via Chromium extension or HA dashboard theme
**Warning signs:** Text gets highlighted when scrolling, accidental back-navigation on swipe

### Pitfall 4: xdotool Does Not Work Under Wayland

**What goes wrong:** xdotool and xprintidle commands fail silently or return errors.
**Why it happens:** These are X11-only tools. Wayland uses a different protocol.
**How to avoid:**
- Verify the Pi is running X11 (not Wayland): `echo $XDG_SESSION_TYPE` should return "x11"
- The project explicitly uses X11 (confirmed in PROJECT.md: "Display server: X11 with GNOME desktop")
- If Pi is on Wayland, switch via: `sudo raspi-config nonint do_wayland W1`
**Warning signs:** xdotool commands return "Error: Can't open display", xprintidle returns nothing

### Pitfall 5: Service Coordination Conflicts with Touchscreen Reboot

**What goes wrong:** WiFi watchdog triggers reboot at the same time touchscreen-check.sh triggers reboot, or both services conflict during boot sequence.
**Why it happens:** Multiple services with reboot capability without coordination.
**How to avoid:**
- WiFi watchdog uses its OWN flag file (different path from touchscreen flag file)
- WiFi watchdog timer starts AFTER touchscreen-check.service completes (use `After=touchscreen-check.service`)
- Both services share the same flag-file pattern but with separate files
- WiFi watchdog waits 120+ seconds after boot (touchscreen check completes within 60+timeout seconds)
**Warning signs:** Conflicting reboots in journal logs, unexpected reboot timing

### Pitfall 6: Kiosk Service Fails Because Desktop Not Ready

**What goes wrong:** Chromium launch fails because X11 session is not fully initialized when systemd starts the service.
**Why it happens:** `graphical.target` fires before the full desktop session is ready. Chromium needs DISPLAY=:0 and a running X server.
**How to avoid:**
- Keep the existing autostart approach (`~/.config/autostart/kiosk.desktop`) for launching the kiosk
- Use a separate watchdog process or script wrapper to handle restarts, rather than making Chromium a system service
- If using systemd user service, ensure it depends on `graphical-session.target` (not `graphical.target`)
- Include an explicit sleep (5-10s) before Chromium launch
**Warning signs:** Chromium fails on boot but works when started manually, "cannot open display" in logs

## Code Examples

Verified patterns from existing project code and official sources:

### WiFi Watchdog Script Structure

```bash
#!/bin/bash
set -euo pipefail

# WiFi watchdog — detects network failures and recovers.
# Uses flag-file protection to prevent infinite reboot loops.
# All configurable values loaded from config.json via lib/config.sh.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/lib/config.sh"

# Load configuration
WIFI_SSID="$(cfg_require '.wifi.ssid')"
WIFI_PASSWORD="$(cfg_require '.wifi.password')"
DASHBOARD_URL="$(cfg_require '.dashboard.url')"
FLAG_FILE="/var/run/wifi-reboot-attempted"
LOG_TAG="wifi-watchdog"

log_message() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

check_network() {
  # Stage 1: Ping default gateway
  local gateway
  gateway=$(ip route | grep default | awk '{print $3}' | head -1)
  if [ -n "$gateway" ] && ping -c 1 -W 5 "$gateway" &>/dev/null; then
    return 0
  fi

  # Stage 2: Ping public DNS
  if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
    return 0
  fi

  # Stage 3: DNS resolution
  if host google.com &>/dev/null; then
    return 0
  fi

  # Stage 4: HTTP check to dashboard
  if curl --max-time 10 --silent --output /dev/null "$DASHBOARD_URL"; then
    return 0
  fi

  return 1  # All checks failed
}

# ... (recovery logic with flag-file protection)
```

### systemd Timer for WiFi Watchdog

```ini
# wifi-watchdog.timer
[Unit]
Description=WiFi Watchdog Timer
After=touchscreen-check.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=30s

[Install]
WantedBy=timers.target
```

```ini
# wifi-watchdog.service
[Unit]
Description=WiFi Watchdog Check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/home/shaun/dashboard-project/watchdog/wifi-watchdog.sh
StandardOutput=journal
StandardError=journal
```

### Kiosk Script Modifications (Chromium Flags)

```bash
# Additional flags for touch handling and crash prevention
# (added to existing kiosk.sh chromium-browser launch)
chromium-browser \
  --kiosk \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-restore-session-state \
  --disable-features=TranslateUI \
  --no-first-run \
  --fast \
  --fast-start \
  --disable-default-apps \
  --password-store=basic \
  --display=:0 \
  --user-data-dir="$USER_DATA_DIR" \
  --disable-touch-drag-drop \
  --overscroll-history-navigation=0 \
  --disable-pinch \
  "$DASHBOARD_URL"
```

### Idle Detection + Auto-Return Script

```bash
#!/bin/bash
set -euo pipefail

# Browser watchdog — returns to home page after inactivity timeout.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$REPO_ROOT/lib/config.sh"

INACTIVITY_TIMEOUT="$(cfg_get '.browser.inactivity_timeout_seconds')"
INACTIVITY_TIMEOUT="${INACTIVITY_TIMEOUT:-600}"
DASHBOARD_URL="$(cfg_require '.dashboard.url')"
IDLE_TIMEOUT_MS=$((INACTIVITY_TIMEOUT * 1000))
LOG_TAG="browser-watchdog"

log_message() {
  logger -t "$LOG_TAG" "$1"
  echo "$1"
}

log_message "Browser watchdog started (idle timeout: ${INACTIVITY_TIMEOUT}s)"

while true; do
  IDLE_MS=$(DISPLAY=:0 xprintidle 2>/dev/null || echo "0")
  if [ "$IDLE_MS" -gt "$IDLE_TIMEOUT_MS" ]; then
    log_message "Idle timeout reached (${IDLE_MS}ms > ${IDLE_TIMEOUT_MS}ms), reloading dashboard"
    DISPLAY=:0 xdotool key F5
    # Wait full timeout before checking again to avoid rapid-fire reloads
    sleep "$INACTIVITY_TIMEOUT"
  fi
  sleep 10
done
```

### Scheduled Soft Reboot Timer

```ini
# scheduled-reboot.timer
[Unit]
Description=Scheduled Soft Reboot Timer

[Timer]
OnBootSec=48h
AccuracySec=1h

[Install]
WantedBy=timers.target
```

```ini
# scheduled-reboot.service
[Unit]
Description=Scheduled Soft Reboot
After=touchscreen-check.service

[Service]
Type=oneshot
ExecStart=/usr/bin/systemctl reboot
StandardOutput=journal
StandardError=journal
```

Note: `OnBootSec=48h` means the reboot happens 48 hours after the last boot, creating a rolling 2-day cycle. This is configured from `browser.scheduled_reboot_interval_hours` in config.json.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| wpa_supplicant for WiFi | NetworkManager (nmcli) | RPi OS Bookworm (2023) | WiFi management commands changed; use `nmcli connection` not `wpa_cli` |
| cron for periodic tasks | systemd timers | Gradual, standard by 2024 | Better boot integration, logging, dependency awareness |
| `--disable-session-crashed-bubble` alone | sed Preferences file + flag | Chromium ~v50+ | Flag alone insufficient; must modify Preferences JSON |
| Browser extension for idle reset | xprintidle + xdotool (for X11 kiosks) | Still both viable | Extension approach more elegant but adds deployment complexity; xprintidle simpler for X11 |
| Autostart-only browser launch | systemd service or wrapper script with restart loop | Standard practice 2024+ | Autostart alone has no crash recovery; need supervision layer |

**Deprecated/outdated:**
- **wpa_supplicant direct management:** Replaced by NetworkManager on Bookworm. Don't write to `/etc/wpa_supplicant/wpa_supplicant.conf` directly.
- **cron for watchdogs:** systemd timers are preferred because they integrate with boot ordering and service dependencies.
- **`--disable-session-crashed-bubble` as sole solution:** Insufficient alone; must be combined with Preferences file modification.

## Config Values Already Present

Phase 1 already added these config sections to `config.json.template` (no schema changes needed for Phase 2):

```json
{
  "wifi": {
    "ssid": "__WIFI_SSID__",
    "password": "__WIFI_PASSWORD__"
  },
  "browser": {
    "inactivity_timeout_seconds": 600,
    "scheduled_reboot_interval_hours": 48
  }
}
```

All Phase 2 scripts read from these existing config keys via `cfg_get`/`cfg_require`.

Additional config values that may be needed (add to `config.json.template` if desired):

| Key Path | Default | Purpose |
|----------|---------|---------|
| `watchdog.wifi_check_interval_minutes` | 5 | How often the WiFi watchdog timer fires |
| `watchdog.wifi_boot_delay_seconds` | 120 | How long to wait after boot before first check |
| `system.reboot_flag_file_wifi` | `/var/run/wifi-reboot-attempted` | WiFi watchdog flag file path |
| `system.log_tag_wifi` | `wifi-watchdog` | Journal log tag for WiFi watchdog |
| `system.log_tag_browser` | `browser-watchdog` | Journal log tag for browser watchdog |

**Recommendation:** Use hardcoded sensible defaults in scripts (like Phase 1's `cfg_get` with fallback) rather than adding all of these to config.json. Only expose values users would actually change. The WiFi check interval and boot delay are implementation details, not user-facing config.

## Open Questions

1. **Kiosk Browser as systemd Service vs. Autostart Wrapper**
   - What we know: The current approach uses `~/.config/autostart/kiosk.desktop`. Moving to a systemd user service provides `Restart=on-failure` for free, but requires careful X11 session integration.
   - What's unclear: Whether a systemd user service can reliably access DISPLAY=:0 after graphical-session.target on the Pi's specific X11 setup (GNOME + auto-login).
   - Recommendation: Keep autostart for initial Chromium launch, but wrap kiosk.sh in a restart loop (`while true; do chromium-browser ...; sleep 5; done`) OR add a separate monitoring script that checks if Chromium is running and relaunches it. This provides crash recovery without the complexity of systemd user service X11 integration. The monitoring approach matches BRW-02 ("auto-restarts on crash via systemd service supervision") while being practical.

2. **xdotool F5 vs. URL Navigation for Auto-Return**
   - What we know: F5 reloads the current page. If the user navigated to a sub-page, F5 stays on that sub-page, not the home dashboard.
   - What's unclear: Whether HA dashboards always return to the default view on reload, or if the URL includes the current view state.
   - Recommendation: Use `xdotool key ctrl+l` followed by typing the dashboard URL and pressing Enter. This guarantees navigation to the configured home URL regardless of current page state. Test on Pi to confirm xdotool can type URLs into Chromium's address bar in kiosk mode. Fallback: use `xdotool key F5` if URL typing doesn't work in kiosk mode (kiosk mode hides the address bar).

3. **Touch Scrolling: Chromium Flags vs. CSS Injection**
   - What we know: `--disable-touch-drag-drop` prevents drag-drop behavior. CSS `user-select: none` prevents text selection. HA dashboard may already handle touch scrolling if Chromium flags are correct.
   - What's unclear: Whether the flags alone are sufficient on the specific Pi 4 + ILITEK touchscreen hardware, or if CSS injection is also needed.
   - Recommendation: Try Chromium flags first (matching BRW-01 requirement: "try Chromium flags first, explore alternative browser only if flags fail on hardware"). Add `--disable-touch-drag-drop` and `--overscroll-history-navigation=0` to kiosk.sh. Test on Pi hardware. If text selection still occurs, add CSS injection as a second step. CSS can be injected via a simple Chromium extension or via HA dashboard theme configuration.

4. **Browser Monitoring: Process Check vs. Window Check**
   - What we know: `pgrep chromium` checks if any Chromium process exists. `xdotool search --class chromium` checks if a Chromium window exists on the display.
   - What's unclear: Whether Chromium can have background processes running (from crash remnants) without a visible window.
   - Recommendation: Use `xdotool search --class chromium` for window detection (more accurate for "is the dashboard visible?"). If no window found, `pkill chromium` (clean up remnants) then relaunch. This covers both "Chromium crashed entirely" and "Chromium crashed but left zombie processes."

## Sources

### Primary (HIGH confidence)

- Existing project codebase: `touchscreen-check.sh` flag-file pattern, `kiosk.sh` Chromium flags, `lib/config.sh` loader, `bootstrap.sh` service generation pattern
- [systemd.service man page](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) - Restart policies, WatchdogSec, StartLimitBurst
- [systemd.timer man page](https://www.freedesktop.org/software/systemd/man/latest/systemd.timer.html) - OnBootSec, OnUnitActiveSec
- [Jeff Geerling - nmcli for WiFi on Raspberry Pi OS 12 'Bookworm'](https://www.jeffgeerling.com/blog/2023/nmcli-wifi-on-raspberry-pi-os-12-bookworm/) - nmcli commands and NetworkManager patterns
- [Raspberry Pi Documentation - Configuring Networking](https://github.com/raspberrypi/documentation/blob/develop/documentation/asciidoc/computers/configuration/configuring-networking.adoc) - Official networking docs

### Secondary (MEDIUM confidence)

- [Pi Forums - Network watchdog?](https://forums.raspberrypi.com/viewtopic.php?t=390584) - Community WiFi watchdog patterns
- [Pi Forums - Script to ensure WiFi connectivity](https://forums.raspberrypi.com/viewtopic.php?t=342255) - WiFi recovery approaches
- [Pi Forums - disable chromium restore session kiosk mode](https://forums.raspberrypi.com/viewtopic.php?t=203921) - Preferences file sed fix, confirmed across multiple posts
- [Pi Forums - Stop chromium to show "restore session" pop-up](https://forums.raspberrypi.com/viewtopic.php?t=212015) - Additional confirmation of sed approach
- [Luca Scalzotto - Setting up a Chromium kiosk on a Raspberry Pi](https://www.scalzotto.nl/posts/raspberry-pi-kiosk/) - systemd user service for kiosk with crash recovery
- [SmartUpWorld - Chromium Kiosk Mode Guide](https://smartupworld.com/chromium-kiosk-mode/) - Touch flags reference
- [MDN - user-select CSS property](https://developer.mozilla.org/en-US/docs/Web/CSS/Reference/Properties/user-select) - CSS text selection prevention
- [GitHub - xprintidle](https://github.com/g0hl1n/xprintidle) - X11 idle time utility
- [Pi Forums - Scheduled Reboots: Keep your Pi Fresh!](https://forums.raspberrypi.com/viewtopic.php?t=126106) - Scheduled reboot patterns
- [systemd by example - Part 2: Dependencies](https://seb.jambor.dev/posts/systemd-by-example-part-2-dependencies/) - After, Wants, Requires explained
- [GitHub - Automatically restarting Chromium Kiosk](https://gist.github.com/magiausde/44ccb4184268a8a0c0394f63d00fb08d) - Wayland Chromium auto-restart gist

### Tertiary (LOW confidence)

- [Pi Forums - Auto refresh using xdotool not working](https://forums.raspberrypi.com/viewtopic.php?t=289232) - xdotool may need DISPLAY export (verified: project already uses DISPLAY=:0)
- [Pi Forums - Chromium and touch scrolling doesn't work with labwc](https://forums.raspberrypi.com/viewtopic.php?t=381610) - Touch scrolling issues on Wayland (not applicable: project uses X11)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All tools are standard Linux/Pi utilities, already available or trivially installable
- Architecture: HIGH - Follows existing project patterns (flag files, config loaders, systemd services, bash scripts)
- WiFi watchdog: HIGH - Pattern is well-documented across multiple community sources; mirrors existing touchscreen-check.sh
- Browser crash recovery: MEDIUM-HIGH - sed Preferences fix is well-confirmed; systemd vs. autostart trade-off needs Pi validation
- Touch scrolling: MEDIUM - Chromium flags are documented but hardware-specific behavior needs Pi testing
- Idle detection (xprintidle): HIGH - Standard X11 tool, confirmed project uses X11
- Pitfalls: HIGH - Boot-loop, restore dialog, service coordination all well-documented with clear prevention strategies

**Research date:** 2026-02-11
**Valid until:** 2026-03-11 (30 days - stable domain, standard Linux tools)
