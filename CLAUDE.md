# Claude Code Guidelines

This document helps Claude Code work effectively with this Raspberry Pi kiosk dashboard project.

## Project Overview

A Raspberry Pi-based kiosk running a Chromium browser in fullscreen mode to display a Home Assistant dashboard for family chore management.

**What's Working:**
- `scripts/kiosk.sh` - Launches Chromium in kiosk mode on boot
- `config/autostart/kiosk.desktop` - Template for autostart configuration
- `scripts/setup/bootstrap.sh` - Automated provisioning script
- `scripts/setup/verify.sh` - Post-setup verification script
- `scripts/display_control.py` - HDMI display power control (future feature)
- Git version control with clear commit history

## Project Structure

```
~/dashboard-project/
├── scripts/
│   ├── kiosk.sh             # Browser startup script (core functionality)
│   ├── display_control.py   # Display power control (future use)
│   └── setup/
│       ├── bootstrap.sh     # Automated provisioning
│       └── verify.sh        # Post-setup checks
├── config/
│   └── autostart/
│       └── kiosk.desktop    # Autostart template (uses __REPO_ROOT__ token)
├── readme.md                # User-facing documentation
└── CLAUDE.md               # This file
```

## Key Commands

### Setup & Provisioning
```bash
# Run after cloning to a fresh Pi
./scripts/setup/bootstrap.sh

# Verify everything is configured correctly
./scripts/setup/verify.sh
```

### Kiosk Control
```bash
# Test kiosk mode manually
./scripts/kiosk.sh

# Stop kiosk mode (via SSH)
pkill chromium
```

### Display Control (Future Feature)
```bash
# Turn display on/off
python3 scripts/display_control.py on
python3 scripts/display_control.py off

# Check status
python3 scripts/display_control.py status

# Run on schedule
python3 scripts/display_control.py schedule --on-time 07:00 --off-time 22:00
```

## Coding Conventions

### Shell Scripts
- Use `bash` with `set -euo pipefail`
- Two-space indentation
- Quote all variables
- Keep functions small with descriptive verb names
- Lowercase filenames with hyphens (`kiosk.desktop`, `bootstrap.sh`)

### Python Scripts
- Type hints where applicable
- Descriptive function and variable names
- Standard library preferred over external dependencies

### Templates
- Preserve `__REPO_ROOT__` token in templates
- Bootstrap script renders these during setup

## Testing & Verification

- `verify.sh` is the central smoke test
- Extend it when adding new dependencies
- Document manual verification steps for hardware features (touchscreen, GPIO, display power)

## Git Workflow

### Commit Messages
- Present tense, concise subject lines under 70 characters
- Example: `sync autostart template`
- Group logical changes per commit
- Describe observable behavior in commit body when needed

### What to Track
- Configuration files and templates
- Scripts and automation
- Documentation

### What NOT to Track (see .gitignore)
- Python cache (`__pycache__/`, `*.pyc`)
- Editor files (`*.swp`, `.vscode/`, `.idea/`)
- OS artifacts (`.DS_Store`)

## Important Notes

### Security
- Never hard-code secrets, IPs, or dashboard URLs beyond documented placeholders
- Use environment variables or template tokens instead

### Future Features Planned
- Display power control (on/off scheduling)
- Touchscreen verification on reboot
- Additional automation as needed

### Bootstrap Recovery
- Re-run `bootstrap.sh` after OS updates or Pi rebuilds
- Ensures permissions and autostart files remain current
- Designed for quick recovery from failures
