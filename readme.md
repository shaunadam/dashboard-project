# Dashboard Pi

A wall-mounted Raspberry Pi kiosk that displays a Home Assistant week-planner
dashboard on a touchscreen. It boots to fullscreen with zero human intervention
and integrates with Home Assistant via MQTT for remote display power control.

## Hardware

- **Raspberry Pi 4** (Model B)
- **15" USB touchscreen** (ILITEK controller, USB ID `222a:0001`)
- MicroSD card (bootable system)

### Touchscreen cold-boot issue

The USB touchscreen controller doesn't reliably enumerate on a cold boot
(power cycle) but works fine after a warm reboot. `touchscreen-check.service`
handles this automatically:

1. Waits ~60s after boot for hardware initialization.
2. Checks whether the touchscreen (`222a:0001`) is detected.
3. If not, performs **one** automatic reboot (a persistent flag file at
   `/var/lib/dashboard-project/touchscreen-reboot-attempted` prevents an
   infinite reboot loop — if the touchscreen is still missing after that one
   reboot, the service gives up and logs an error for manual investigation).

First boot after a full power loss takes ~2-3 minutes (includes the one
auto-reboot). A normal `sudo reboot` reaches the dashboard immediately.

### Operating system

- Raspberry Pi OS with Desktop (64-bit), Wayland compositor
- Hostname: `dashboard.local`
- Auto-login enabled for kiosk mode

## Software stack

- **Chromium** — kiosk-mode display, launched by `kiosk/kiosk.sh`
- **Python 3** + **paho-mqtt** — MQTT client for Home Assistant integration
- **wlopm** — Wayland display power control (not in apt; see Bootstrap below)
- **jq** — JSON config generation/parsing in the shell scripts
- **unclutter** — hides the mouse cursor when idle
- **onboard** — on-screen keyboard for touch input (e.g. entering WiFi
  credentials during recovery)
- **NetworkManager (`nmcli`)** — used by the WiFi watchdog for detection and
  recovery

## Home Assistant integration

- Home Assistant + the MQTT broker run on a separate VM (basement server) —
  the Pi is a display + MQTT client only.
- `mqtt/mqtt_listener.py` subscribes to a command topic and publishes
  status/availability, and on connect publishes an MQTT auto-discovery
  payload so a "Dashboard Pi" device with a display power switch entity
  appears in Home Assistant automatically — no `configuration.yaml` editing
  needed.

## Project structure

```
dashboard-project/
├── config.json.template        # Configuration schema reference
├── config.json                 # Active config (git-ignored, created by bootstrap)
├── lib/
│   ├── config.sh                # Bash config loader (cfg_get, cfg_require)
│   └── config.py                # Python config loader (get, require)
├── kiosk/
│   └── kiosk.sh                  # Chromium kiosk launcher + restart loop
├── display/
│   └── display_control.py        # HDMI display power control (wlopm)
├── mqtt/
│   └── mqtt_listener.py          # MQTT subscriber + HA auto-discovery
├── touchscreen/
│   └── touchscreen-check.sh      # Boot-time touchscreen detection + one auto-reboot
├── watchdog/
│   ├── wifi-watchdog.sh           # Network failure detection + staged recovery
│   └── browser-watchdog.sh        # Idle auto-return + WiFi-recovery reload
├── setup/
│   ├── bootstrap.sh                # Automated provisioning
│   ├── verify.sh                   # Post-setup verification
│   ├── config-backup.sh            # Export config to backup
│   ├── config-restore.sh           # Restore config from backup
│   ├── switch-branch.sh            # Switch branch + regenerate services + restart
│   └── systemd-units.sh            # Shared systemd unit definitions (sourced by
│                                    #   bootstrap.sh and switch-branch.sh)
├── test-wifi-watchdog.sh       # Manual WiFi-drop test harness (see below)
└── readme.md                   # This file
```

## Installation & setup

### Automated bootstrap (recommended)

Run after cloning to a fresh Pi:

```bash
./setup/bootstrap.sh
```

Bootstrap will:
- Install required apt packages (jq, chromium, unclutter, onboard, etc.)
- Prompt for configuration values (dashboard URL, MQTT credentials, WiFi, etc.)
  and generate `config.json`
- Create the persistent state directory (`/var/lib/dashboard-project`) used
  for boot-loop-protection flag files
- Create systemd service/timer files and the kiosk autostart entry
- Set script permissions

**wlopm is not packaged for Raspberry Pi OS** and must be installed
separately (build from source or grab a prebuilt binary for your `wlr`
version) before `display/display_control.py` will work. `setup/verify.sh`
checks for it and will tell you if it's missing.

After bootstrap completes, confirm everything is configured correctly:

```bash
./setup/verify.sh
```

### Initial Pi configuration

1. **Flash the SD card** with Raspberry Pi Imager:
   - Select "Raspberry Pi OS with Desktop (64-bit)"
   - Configure advanced options: enable SSH, set username/password, configure
     WiFi, set hostname `dashboard.local`, set timezone/locale
2. **Enable auto-login:**
   ```bash
   sudo raspi-config
   # System Options → Boot / Auto Login → Desktop Autologin
   ```
3. **Clone the repository:**
   ```bash
   cd ~
   git clone <your-repo-url> dashboard-project
   cd dashboard-project
   ```
4. **Run bootstrap and verify:**
   ```bash
   ./setup/bootstrap.sh
   ./setup/verify.sh
   ```

### Kiosk mode

`kiosk/kiosk.sh` starts Chromium in fullscreen kiosk mode and restarts it if
it ever exits (crash or otherwise), clearing crash-restore state first so no
"restore pages?" dialog appears. All configuration (dashboard URL, Chromium
data directory, on-screen keyboard size) is read from `config.json`.

Autostart is configured automatically by `setup/bootstrap.sh`.

## Configuration management

All project configuration lives in a single `config.json` at the repo root.
It's git-ignored so credentials are never committed; the schema (with
placeholder tokens) lives in `config.json.template`.

| Section | Values |
|---------|--------|
| `dashboard` | Home Assistant dashboard URL |
| `mqtt` | Broker address, port, username, password, client ID, topics, heartbeat interval |
| `display` | Wayland display name |
| `touchscreen` | USB device ID, detection wait time |
| `kiosk` | Desktop load wait, on-screen keyboard size, Chromium data directory |
| `wifi` | SSID, password (used by the WiFi watchdog to reapply credentials) |
| `home_assistant` | Auth method |
| `browser` | Inactivity timeout (auto-return to dashboard), scheduled reboot interval |
| `system` | Reboot flag file paths, WiFi recovery signal file, log tags |

### Backup

```bash
./setup/config-backup.sh /path/to/backup.json   # defaults to ~/dashboard-config-backup.json
```

The backup contains MQTT and WiFi credentials — store it securely, off the Pi.

### Restore

```bash
./setup/config-restore.sh /path/to/backup.json
```

Validates the backup (JSON syntax, required keys) before applying it, then
restarts the affected services.

## Resilience

### WiFi watchdog

`watchdog/wifi-watchdog.timer` runs `wifi-watchdog.sh` every 5 minutes. It
validates connectivity in stages (device state → gateway ping → public DNS →
DNS resolution → HTTP check to the dashboard) and, on failure, works through
increasingly disruptive recovery steps: reconnect the WiFi device, cycle the
connection, reapply credentials from `config.json`, restart NetworkManager,
and finally reboot — with a persistent flag file
(`/var/lib/dashboard-project/wifi-reboot-attempted`) to prevent a reboot loop
if WiFi genuinely stays down. On successful recovery it signals the browser
watchdog (via `/tmp/wifi-recovered`, configurable) to reload the dashboard.

Manual test harness: `sudo bash ./test-wifi-watchdog.sh` disconnects WiFi
under a systemd scope (survives SSH disconnects) with a safety net to restore
connectivity; watch it with `journalctl -u wifi-test --no-pager`.

### Browser watchdog

`watchdog/browser-watchdog.service` polls Chromium's current URL via the
Chrome DevTools Protocol (`--remote-debugging-port=9222`, set in
`kiosk.sh`). If the browser has been away from the dashboard URL longer than
`browser.inactivity_timeout_seconds` (default 5 minutes), or a WiFi-recovery
signal appears, it kills Chromium so the kiosk restart loop relaunches it at
the dashboard URL.

### Scheduled reboot

`scheduled-reboot.timer` performs a soft reboot every
`browser.scheduled_reboot_interval_hours` (default 48h) as a periodic reset.

## MQTT display control

The `mqtt-listener` service (installed as a **systemd user service** — it
needs the graphical session to reach the Wayland compositor for `wlopm`)
subscribes to a command topic and publishes status/availability.

- **Command topic** (subscribe): `dashboard/display/command` — accepts `on`, `off`, `status`
- **Status topic** (publish): `dashboard/display/status` — `on`, `off`, `unknown`
- **Availability topic** (publish): `dashboard/display/availability` — `online`, `offline`

Topics are configurable in `config.json`. On first connection the listener
publishes a retained MQTT auto-discovery payload, so the display switch
entity (`switch.dashboard_display`) appears in Home Assistant without manual
configuration.

### Service management

```bash
# mqtt-listener is a user service
systemctl --user status mqtt-listener.service
journalctl --user -u mqtt-listener -f
systemctl --user restart mqtt-listener.service

# everything else is a system service
systemctl status touchscreen-check.service wifi-watchdog.timer browser-watchdog.service
journalctl -u browser-watchdog -u wifi-watchdog -u touchscreen-check -f
```

### Manual testing

```bash
mosquitto_pub -h <broker-ip> -u <username> -P <password> -t "dashboard/display/command" -m "on"
mosquitto_pub -h <broker-ip> -u <username> -P <password> -t "dashboard/display/command" -m "off"
mosquitto_sub -h <broker-ip> -u <username> -P <password> -t "dashboard/display/status"
```

Or directly on the Pi:

```bash
python3 ~/dashboard-project/display/display_control.py on
python3 ~/dashboard-project/display/display_control.py off
python3 ~/dashboard-project/display/display_control.py status   # queries actual hardware state via wlopm
```

### Home Assistant automation examples

```yaml
automation:
  - alias: "Dashboard Display On - Motion Detected"
    trigger:
      - platform: state
        entity_id: binary_sensor.living_room_motion
        to: "on"
    action:
      - service: switch.turn_on
        target:
          entity_id: switch.dashboard_display

  - alias: "Dashboard Display Off - Bedtime"
    trigger:
      - platform: time
        at: "22:00:00"
    action:
      - service: switch.turn_off
        target:
          entity_id: switch.dashboard_display
```

## Development workflow

`main` is production; feature branches (`feat/...`, `fix/...`) are for
development. Develop on a laptop, push, then deploy to the Pi with one
command:

```bash
ssh pi '~/dashboard-project/setup/switch-branch.sh <branch-name>'
```

This will:
1. Abort if the Pi has uncommitted changes (investigate, don't force).
2. Fetch from origin and switch to the target branch.
3. Regenerate systemd unit files (paths can differ between branches) and
   restart the long-running services (`mqtt-listener`, `browser-watchdog`) so
   the new code takes effect immediately.
4. Run `verify.sh`.

**Note:** `config.json` is git-ignored, so it persists across branch
switches. If switching to a branch never bootstrapped on this Pi, run
`./setup/bootstrap.sh` afterward.

When a change survives a real reboot (`ssh pi sudo reboot`, wait ~3 min,
verify again), merge to `main` and switch the Pi back:

```bash
ssh pi '~/dashboard-project/setup/switch-branch.sh main'
```

## Recovery

### Fast recovery from SD card failure

1. Flash a fresh Raspberry Pi OS (64-bit Desktop; configure SSH/WiFi/hostname).
2. Clone the repo: `git clone <your-repo-url> dashboard-project && cd dashboard-project`
3. Run bootstrap: `./setup/bootstrap.sh`
4. Restore your config backup (if you have one): `./setup/config-restore.sh /path/to/backup.json`
5. Reboot: `sudo reboot`

**A config backup is essential for fast recovery.** Without one you'll
re-enter every configuration value (MQTT credentials, dashboard URL, WiFi
password, etc.) during the bootstrap prompts. With one, steps 3-5 take under
a minute.

### Keeping a config backup

```bash
./setup/config-backup.sh ~/dashboard-config-backup.json
```

Store it off the Pi (USB drive, cloud storage, another machine) — it
contains MQTT and WiFi credentials, so keep it secure.

## Resources

- [Home Assistant Documentation](https://www.home-assistant.io/docs/)
- [Raspberry Pi Documentation](https://www.raspberrypi.org/documentation/)
- [paho-mqtt Documentation](https://eclipse.dev/paho/files/paho.mqtt.python/html/client.html)

## Project goals

1. **Primary:** wall-mounted family chore/week-planner dashboard
2. **Secondary:** general-purpose dashboard (calendar, smart home, weather)
3. **Reliability:** cold boot to a working, touch-responsive dashboard with
   zero human intervention
4. **Maintenance:** minimal physical access required after installation
