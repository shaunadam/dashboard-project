# Dashboard Pi

A wall-mounted Raspberry Pi kiosk that displays a Home Assistant week-planner
dashboard. It boots to fullscreen with zero human intervention and integrates
with Home Assistant via MQTT for remote display power control.

## Hardware

- **Raspberry Pi 4** (Model B)
- **15" display**
- **Wireless mouse** (Logitech Unifying receiver) — the only input device
- MicroSD card (bootable system)

The project previously drove a 15" USB touchscreen (ILITEK controller, USB ID
`222a:0001`). That panel proved unreliable — it stopped enumerating over USB —
and was replaced by a wireless mouse. All touchscreen detection, the
`touchscreen-check` boot service, and the on-screen keyboard have been removed;
see the git history if you ever need them back.

### Operating system

- Raspberry Pi OS with Desktop (64-bit), Wayland compositor
- Hostname: `dashboard.local`
- Auto-login enabled for kiosk mode

## Software stack

- **Chromium** — kiosk-mode display, launched by `kiosk/kiosk.sh`
- **Python 3** + **paho-mqtt** — MQTT client for Home Assistant integration
- **wlopm** — Wayland display power control (not in apt; see Bootstrap below)
- **jq** — JSON config generation/parsing in the shell scripts
- **unclutter** — hides the mouse cursor while it's idle, so the wall display
  stays clean; moving the mouse brings it back
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
├── config.json                 # Non-secret configuration (tracked in git)
├── secrets.json.template       # Schema for the credentials file
├── secrets.json                # Credentials only (git-ignored, mode 600)
├── lib/
│   ├── config.sh                # Bash config loader (cfg_get, cfg_require)
│   └── config.py                # Python config loader (get, require)
├── kiosk/
│   └── kiosk.sh                  # Chromium kiosk launcher + restart loop
├── display/
│   └── display_control.py        # HDMI display power control (wlopm)
├── mqtt/
│   └── mqtt_listener.py          # MQTT subscriber + HA auto-discovery
├── watchdog/
│   ├── wifi-watchdog.sh           # Network failure detection + staged recovery
│   └── browser-watchdog.sh        # Idle auto-return + WiFi-recovery reload
├── setup/
│   ├── bootstrap.sh                # Automated provisioning
│   ├── verify.sh                   # Post-setup verification
│   ├── config-backup.sh            # Export secrets.json to a backup
│   ├── config-restore.sh           # Restore secrets.json from a backup
│   ├── migrate-secrets.sh          # Pull credentials out of a pre-split config.json
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
- Install required apt packages (jq, chromium, unclutter, etc.)
- Prompt for the four credentials (MQTT username/password, WiFi SSID/password)
  and generate `secrets.json`. Everything else is already in the tracked
  `config.json`, so there is nothing else to type.
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
data directory) is read from `config.json`.

Autostart is configured automatically by `setup/bootstrap.sh`.

## Configuration management

Configuration is split across two files at the repo root, deep-merged by
`lib/config.sh` and `lib/config.py` at load time (secrets win). Every consumer
just asks for a path like `.mqtt.password` and never knows which file the
value came from.

| File | Tracked in git? | Contents |
|------|-----------------|----------|
| `config.json` | **Yes** | Everything that isn't a credential |
| `secrets.json` | No — git-ignored, mode 600 | `mqtt.username`, `mqtt.password`, `wifi.ssid`, `wifi.password` |

That split is what makes the push/pull workflow work: changing a timeout, the
dashboard URL, or a log tag is an ordinary commit that reaches the Pi via
`git pull`, while the four credentials never leave the device. `secrets.json`
mirrors `config.json`'s structure, so its schema is just
`secrets.json.template`.

| Section | Values |
|---------|--------|
| `dashboard` | Home Assistant dashboard URL |
| `mqtt` | Broker address, port, client ID, topics, heartbeat interval (**username/password from `secrets.json`**) |
| `display` | Wayland display name |
| `kiosk` | Desktop load wait, Chromium data directory |
| `wifi` | **SSID and password, from `secrets.json`** (used by the WiFi watchdog to reapply credentials) |
| `home_assistant` | Auth method |
| `browser` | Inactivity timeout (auto-return to dashboard), scheduled reboot interval |
| `system` | WiFi reboot flag file, WiFi recovery signal file, log tags |

`setup/verify.sh` enforces both halves of the deal: it fails if a credential
key ever appears in the tracked `config.json`, and if `secrets.json` isn't
actually git-ignored.

The Pi's LAN address (`192.168.68.75`) is committed. It's an RFC1918 private
address that means nothing outside the network; if you'd rather it weren't in
a public repo, move `dashboard.url` and `mqtt.broker` into `secrets.json` —
the loaders need no change, since the merge is structural.

### Upgrading from the old single-file layout

Older checkouts had one git-ignored `config.json` holding everything. To
convert without retyping passwords:

```bash
mv config.json config.json.legacy
git pull                                        # brings in the tracked config.json
./setup/migrate-secrets.sh config.json.legacy   # writes secrets.json (mode 600)
rm config.json.legacy
```

`setup/bootstrap.sh` does the same automatically if it finds a
`config.json.legacy` next to it.

### Backup

```bash
./setup/config-backup.sh /path/to/backup.json   # defaults to ~/dashboard-secrets-backup.json
```

Only `secrets.json` needs backing up — `config.json` is in git. The backup
contains MQTT and WiFi credentials, so store it securely, off the Pi.

### Restore

```bash
./setup/config-restore.sh /path/to/backup.json
```

Validates the backup (JSON syntax, required keys) before applying it, then
restarts the affected services. It also accepts an old pre-split
`config.json`, taking only the credential keys from it.

## Resilience

### WiFi watchdog

`watchdog/wifi-watchdog.timer` runs `wifi-watchdog.sh` every 5 minutes. It
validates connectivity in stages (device state → gateway ping → public DNS →
DNS resolution → HTTP check to the dashboard) and, on failure, works through
increasingly disruptive recovery steps: reconnect the WiFi device, cycle the
connection, reapply credentials from `secrets.json`, restart NetworkManager,
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
systemctl status wifi-watchdog.timer browser-watchdog.service
journalctl -u browser-watchdog -u wifi-watchdog -f
```

### Retiring a service

Deleting a unit from `setup/systemd-units.sh` doesn't uninstall it — the Pi
only updates via `git pull`, so nothing would ever remove the file already in
`/etc/systemd/system`. Add the unit name to `OBSOLETE_SYSTEM_UNITS` in
`setup/systemd-units.sh` instead; `install_systemd_units` disables and deletes
anything listed there on the next `switch-branch.sh` or `bootstrap.sh` run, and
`verify.sh` fails if a retired unit is still installed.

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
development. The Pi never receives files directly (**no `scp`, ever**) — it
only ever syncs itself from GitHub via `git pull`, wrapped by
`switch-branch.sh`. Everything is edited on a laptop.

### The loop

1. **Branch and edit on your laptop:**
   ```bash
   git checkout -b feat/whatever main
   # edit, test what you can locally (see Testing below)
   git add -A && git commit -m "..."
   git push -u origin feat/whatever
   ```

2. **Deploy to the Pi with one command:**
   ```bash
   ssh pi '~/dashboard-project/setup/switch-branch.sh feat/whatever'
   ```
   This aborts if the Pi has uncommitted changes (investigate, don't force —
   that's the Pi telling you something's there it doesn't expect). Otherwise
   it will:
   1. Fetch from origin and switch to the target branch.
   2. Regenerate systemd unit files (paths can differ between branches) and
      restart the long-running services (`mqtt-listener`, `browser-watchdog`)
      so the new code takes effect immediately.
   3. Run `verify.sh`.

3. **Check it actually worked** — `verify.sh` only confirms things are
   installed/enabled, not that they behave correctly, so also look at the
   display and check logs:
   ```bash
   ssh pi '~/dashboard-project/setup/verify.sh'
   ssh pi 'journalctl -u browser-watchdog -u wifi-watchdog -n 100 --no-pager'
   ssh pi 'journalctl --user -u mqtt-listener -n 50 --no-pager'   # mqtt-listener is a user service
   ```

4. **If the change touches boot behavior, reboot-test before trusting it:**
   ```bash
   ssh pi sudo reboot
   # wait ~3 min
   ssh pi '~/dashboard-project/setup/verify.sh'
   ```

5. **Once it's solid, merge to `main` on your laptop and switch the Pi back:**
   ```bash
   git checkout main && git merge feat/whatever && git push
   ssh pi '~/dashboard-project/setup/switch-branch.sh main'
   ```

**Note:** `secrets.json` is git-ignored, so credentials persist across branch
switches; `config.json` is tracked, so settings changes ride along with the
branch. If `secrets.json` is missing after a switch, run
`./setup/bootstrap.sh`.

### Testing without the Pi

Unit-test `mqtt/` and `display/` with mocked `subprocess`/`paho`. Anything
touching `wlopm`, Chromium CDP, `nmcli`, or USB needs the real Pi — say so in
the commit/PR message rather than claiming it's verified.

## Recovery

### Fast recovery from SD card failure

1. Flash a fresh Raspberry Pi OS (64-bit Desktop; configure SSH/WiFi/hostname).
2. Clone the repo: `git clone <your-repo-url> dashboard-project && cd dashboard-project`
3. Restore your secrets backup (if you have one):
   `./setup/config-restore.sh /path/to/backup.json` — otherwise bootstrap will
   prompt for the four credentials
4. Run bootstrap: `./setup/bootstrap.sh`
5. Reboot: `sudo reboot`

Everything except the four credentials is restored by the `git clone` itself,
since `config.json` is tracked.

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
3. **Reliability:** cold boot to a working dashboard with zero human
   intervention
4. **Maintenance:** minimal physical access required after installation
