# Repository Guidelines

## Project Layout
- `scripts/` holds automation entry points: `kiosk.sh` launches Chromium in kiosk mode, while `setup/bootstrap.sh` and `setup/verify.sh` provision and audit the Pi environment.
- `config/autostart/kiosk.desktop` is the template autostart entry; it is rendered with the repo path during bootstrap and synced to `~/.config/autostart`.
- `archive/` stores legacy USB reset helpers kept for reference. Avoid modifying files here unless you are reviving the workflow.
- `readme.md` documents hardware expectations and kiosk configuration; keep it in sync with any operational changes you introduce.

## Build, Test, and Development Commands
- `./scripts/setup/bootstrap.sh` installs required apt packages, ensures autostart wiring, and toggles Docker when `INSTALL_DOCKER=1`.
- `./scripts/setup/verify.sh` confirms commands, Python modules, and autostart state; run it after provisioning and whenever dependencies change.
- `./scripts/kiosk.sh` can be started manually (e.g., `DISPLAY=:0 ./scripts/kiosk.sh`) to confirm Chromium kiosk behavior before wiring it into autostart.

## Coding Style & Naming Conventions
- Shell scripts use `bash`, `set -euo pipefail`, two-space indentation, and quoted variables; keep functions small and prefer descriptive verbs (`ensure_apt_packages`).
- File names are lowercase with hyphens where needed (`kiosk.desktop`, `usb-reset.service`). Match these patterns when adding new scripts or systemd units.
- When editing templates, preserve the `__REPO_ROOT__` token so bootstrap can render paths correctly.

## Testing Guidelines
- Treat `verify.sh` as the central smoke test; extend it when you add new dependencies or require additional validation steps.
- For hardware-facing changes, document manual verification steps (e.g., touchscreen, GPIO) in the PR and, when possible, capture automated checks in new scripts under `scripts/`.

## Commit & Pull Request Guidelines
- Follow the existing history: concise, present-tense subject lines under ~70 characters (e.g., `sync autostart template`).
- Group logical changes per commit and describe observable behavior in the body when context is needed.


## Device & Security Notes
- Never hard-code secrets, IPs, or dashboard URLs beyond the documented placeholders; use environment variables or template tokens instead.
- Re-run `bootstrap.sh` after OS updates or Pi rebuilds to ensure permissions and autostart files remain current.
