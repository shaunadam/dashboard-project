# Dashboard Pi — Claude context

Wall-mounted Raspberry Pi 4 + 15" USB touchscreen running Chromium in kiosk mode
showing a Home Assistant dashboard. Raspberry Pi OS 64-bit, Wayland, hostname
`dashboard.local` (ssh alias `pi`). Home Assistant + MQTT broker live on a separate
VM in the basement; the Pi is a display + MQTT client only.

## Non-negotiables
- The Pi must cold-boot to the week planner page with working touch and zero intervention.
- `config.json` holds credentials and is git-ignored. Never commit it. Schema lives in
  `config.json.template`; if you add a config key, add it to the template, `lib/config.sh`,
  `lib/config.py`, `setup/bootstrap.sh`, and `setup/verify.sh`.
- All files are LF. Shell scripts must stay POSIX bash; the Pi has no dev tooling beyond
  python3, jq, git.
- Never `scp` files to the Pi. The Pi only ever runs `git pull` via `setup/switch-branch.sh`.

## Dev loop
1. Branch from `main` (`feat/...` or `fix/...`).
2. Edit here; commit; push.
3. Deploy to Pi: `ssh pi '~/dashboard-project/setup/switch-branch.sh <branch>'`
   (aborts if the Pi has uncommitted changes — investigate, don't force).
4. Verify: `ssh pi '~/dashboard-project/setup/verify.sh'`
5. Logs: `ssh pi 'journalctl -u mqtt-listener -u browser-watchdog -u wifi-watchdog -n 100 --no-pager'`
   and `ssh pi 'journalctl --user -u mqtt-listener -n 50 --no-pager'` (mqtt-listener is a user service).
6. When it survives a real reboot (`ssh pi sudo reboot`, wait ~3 min, verify again), merge to `main`
   and switch the Pi back: `ssh pi '~/dashboard-project/setup/switch-branch.sh main'`.

## Layout
- `kiosk/kiosk.sh` — Chromium launcher with restart loop (autostart on login)
- `mqtt/` — HA MQTT discovery + display on/off listener
- `display/display_control.py` — wlopm power control
- `watchdog/` — wifi + browser watchdogs (root + user services)
- `touchscreen/` — cold-boot USB re-enumeration fix (one auto-reboot)
- `setup/` — bootstrap / verify / backup / restore / switch-branch
- `.planning/` — GSD roadmap, research, phase plans. Read `.planning/STATE.md`
  and `.planning/ROADMAP.md` before starting a phase. Phase 3 (tests + cleanup) is next.

## Testing without the Pi
Unit-test `mqtt/` and `display/` with mocked subprocess/paho. Anything touching wlopm,
Chromium CDP, nmcli, or USB needs the real Pi — say so in the PR/commit message.