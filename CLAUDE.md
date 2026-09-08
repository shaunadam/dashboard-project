# Dashboard Pi — Claude context

Wall-mounted Raspberry Pi 4 + 15" USB touchscreen running Chromium in kiosk mode
showing a Home Assistant dashboard. Raspberry Pi OS 64-bit, Wayland, hostname
`dashboard.local` (ssh alias `pi`). Home Assistant + MQTT broker live on a separate
VM in the basement; the Pi is a display + MQTT client only.

## Non-negotiables
- The Pi must cold-boot to the week planner page with working touch and zero intervention.
- Config is split in two, deep-merged by the loaders (secrets win):
  `config.json` is **tracked** and holds everything non-secret — edit it here and it
  reaches the Pi via `git pull`. `secrets.json` is git-ignored, mode 600, and holds
  only `mqtt.username`, `mqtt.password`, `wifi.ssid`, `wifi.password`. Never commit it,
  and never let a credential key back into `config.json` (`setup/verify.sh` fails if one
  appears). New non-secret key: add it to `config.json` and any consumer. New secret:
  add it to `secrets.json.template`, `setup/bootstrap.sh`, `setup/migrate-secrets.sh`,
  `setup/config-restore.sh`, and `setup/verify.sh`.
- All files are LF. Shell scripts must stay POSIX bash; the Pi has no dev tooling beyond
  python3, jq, git.
- Never `scp` files to the Pi. The Pi only ever runs `git pull` via `setup/switch-branch.sh`.

## Dev loop
1. Branch from `main` (`feat/...` or `fix/...`).
2. Edit here; commit; push.
3. Deploy to Pi: `ssh pi '~/dashboard-project/setup/switch-branch.sh <branch>'`
   (aborts if the Pi has uncommitted changes — investigate, don't force).
4. Verify: `ssh pi '~/dashboard-project/setup/verify.sh'`
5. Logs: `ssh pi 'journalctl -u browser-watchdog -u wifi-watchdog -u touchscreen-check -n 100 --no-pager'`
   and `ssh pi 'journalctl --user -u mqtt-listener -n 50 --no-pager'` (mqtt-listener is a user service).
6. When it survives a real reboot (`ssh pi sudo reboot`, wait ~3 min, verify again), merge to `main`
   and switch the Pi back: `ssh pi '~/dashboard-project/setup/switch-branch.sh main'`.

## Layout
- `kiosk/kiosk.sh` — Chromium launcher with restart loop (autostart on login)
- `mqtt/` — HA MQTT discovery + display on/off listener
- `display/display_control.py` — wlopm power control
- `watchdog/` — wifi + browser watchdogs (root + user services)
- `touchscreen/` — cold-boot USB re-enumeration fix (one auto-reboot)
- `setup/` — bootstrap / verify / backup / restore / switch-branch / shared systemd unit definitions

## Testing without the Pi
Unit-test `mqtt/` and `display/` with mocked subprocess/paho. Anything touching wlopm,
Chromium CDP, nmcli, or USB needs the real Pi — say so in the PR/commit message.