# Codebase Structure

**Analysis Date:** 2026-02-11

## Directory Layout

```
dashboard-project/
├── scripts/                      # Executable scripts and automation
│   ├── kiosk.sh                  # Chromium fullscreen launcher
│   ├── touchscreen-check.sh      # Hardware detection and auto-recovery
│   ├── mqtt_listener.py          # MQTT subscriber for display control
│   ├── display_control.py        # HDMI display power control utility
│   ├── diagnose-usb.sh           # USB device diagnostic capture
│   ├── usb-rescan.sh             # USB hub re-enumeration utility
│   └── setup/
│       ├── bootstrap.sh          # Automated provisioning script
│       └── verify.sh             # Post-setup validation script
├── config/                       # Configuration files and templates
│   ├── autostart/
│   │   └── kiosk.desktop         # GNOME autostart template
│   ├── systemd/
│   │   ├── touchscreen-check.service   # Touchscreen service template
│   │   ├── mqtt-listener.service       # MQTT listener service template
│   │   └── ha-init.py            # Home Assistant MQTT discovery publisher
│   ├── mqtt.json.template        # MQTT broker config template (git-tracked)
│   └── mqtt.json                 # MQTT broker config instance (git-ignored)
├── .planning/
│   └── codebase/                 # Codebase analysis documents
│       ├── ARCHITECTURE.md       # System design and layer breakdown
│       └── STRUCTURE.md          # This file
├── diagnostics/                  # USB diagnostic reports (git-ignored)
│   └── usb-diag-{type}-{time}.txt
├── .gitignore                    # Excludes cache, configs, credentials
└── readme.md                     # User-facing documentation
```

## Directory Purposes

**scripts/:**
- Purpose: All executable automation and control logic
- Contains: Shell scripts, Python utilities, setup tools
- Key files: See below under "Key File Locations"
- Pattern: Uppercase .sh for bash, lowercase .py for python (matches project convention)

**config/:**
- Purpose: Configuration files, templates, and service definitions
- Contains: Template files with `__TOKEN__` substitutions, systemd service units, autostart definitions
- Key files: See below under "Key File Locations"
- Git tracking: Templates tracked, rendered instances (.gitignore)

**config/autostart/:**
- Purpose: Desktop session autostart definitions
- Contains: .desktop file templates rendered by bootstrap.sh
- Rendered to: `~/.config/autostart/kiosk.desktop` on target system

**config/systemd/:**
- Purpose: Systemd service unit definitions and related scripts
- Contains: .service templates, Python helper scripts for initialization
- Rendered to: `/etc/systemd/system/{service}.service` on target system via bootstrap.sh

**.planning/codebase/:**
- Purpose: Architecture and structure analysis for GSD (Getting Stuff Done) planning
- Contains: Markdown documents describing system design, conventions, testing patterns
- Generator: GSD codebase mapper tool
- Consumers: GSD planning and execution tools

**diagnostics/:**
- Purpose: USB device and kernel log captures for troubleshooting
- Generated: By `scripts/diagnose-usb.sh [cold|warm]`
- Tracking: Not committed (git-ignored), user-generated during troubleshooting

## Key File Locations

**Entry Points:**

- `scripts/kiosk.sh`: Launches Chromium in kiosk mode on desktop session start. Called by `~/.config/autostart/kiosk.desktop` after desktop loads. Responsible for X11 setup, cursor hiding, keyboard startup, screen blanking, and browser launch with Home Assistant URL.

- `scripts/setup/bootstrap.sh`: Primary provisioning script. Installs apt packages, renders config templates, configures MQTT, enables systemd services. Called once during initial Pi setup.

- `scripts/setup/verify.sh`: Validation script. Checks all dependencies installed, Python modules available, service files present and enabled. Called after bootstrap to confirm successful setup.

- `config/systemd/touchscreen-check.service`: Systemd oneshot service template. Rendered and installed to `/etc/systemd/system/touchscreen-check.service`. Runs at multi-user.target before user login to detect USB touchscreen.

- `config/systemd/mqtt-listener.service`: Systemd simple service template. Rendered and installed to `/etc/systemd/system/mqtt-listener.service`. Runs as background daemon after network online, maintains MQTT connection.

**Configuration:**

- `config/mqtt.json.template`: Template with `__MQTT_BROKER__`, `__MQTT_USERNAME__`, `__MQTT_PASSWORD__` tokens. Rendered by bootstrap.sh using user input. Never git-committed, no secrets in repo.

- `config/mqtt.json`: Instance config created from template by bootstrap.sh. Contains actual broker credentials. Git-ignored, file permissions 600 (owner only). Located at `~/dashboard-project/config/mqtt.json` on Pi.

- `config/autostart/kiosk.desktop`: Template with `__REPO_ROOT__` token. Rendered by bootstrap.sh to user's autostart directory. Triggers kiosk.sh on GNOME session start.

- `config/systemd/touchscreen-check.service`: Template with `__REPO_ROOT__` token. Rendered by bootstrap.sh and installed system-wide. Enables automatic touchscreen recovery on cold boot.

- `config/systemd/mqtt-listener.service`: Template with `__REPO_ROOT__` token. Rendered by bootstrap.sh and installed system-wide. Runs MQTT listener daemon.

**Core Logic:**

- `scripts/mqtt_listener.py`: 262-line MQTT client daemon. Contains `DisplayMQTTClient` class encapsulating connection lifecycle, message handling, and status publishing. Entry point at line 260 (`if __name__ == "__main__"`). Signal handlers for graceful shutdown.

- `scripts/display_control.py`: 41-line utility for HDMI power control. Wraps wlopm command with proper Wayland environment setup. Accepts `on|off|status` arguments, exits 0 on success, 1 on invalid arguments.

- `scripts/touchscreen-check.sh`: 51-line boot-time detection script. Waits 60 seconds, checks lsusb for ILITEK device (222a:0001), performs one automatic reboot if missing using flag file at `/var/run/touchscreen-reboot-attempted`.

- `scripts/kiosk.sh`: 36-line X11 display launcher. Sets environment, waits for desktop, hides cursor, starts on-screen keyboard, disables blanking, launches Chromium with specific flags to Home Assistant URL.

**Testing:**

- `.planning/codebase/TESTING.md`: Would document test framework and patterns (not yet analyzed - not in codebase)

**Utilities:**

- `scripts/diagnose-usb.sh`: 98-line diagnostic script. Captures USB device list, verbose USB info, kernel logs, input devices, modules. Output saved to `diagnostics/usb-diag-{cold|warm}-{timestamp}.txt`. User runs manually after cold and warm boots to compare.

- `scripts/usb-rescan.sh`: 63-line USB hub re-enumeration utility. Toggles `/sys/bus/usb/devices/1-1/authorized` to force device re-scan. Checks for VIA Labs hub (2109:3431) and ILITEK device (222a:0001). For manual troubleshooting.

- `config/systemd/ha-init.py`: 145-line Home Assistant MQTT discovery publisher. Creates retained messages for switch and button entities. Run manually once to register display in Home Assistant. Uses paho-mqtt and reads config/mqtt.json.

## Naming Conventions

**Files:**

- Scripts: lowercase with hyphens (`kiosk.sh`, `touchscreen-check.sh`, `mqtt-listener.service`)
- Python: lowercase with underscores (`mqtt_listener.py`, `display_control.py`)
- Templates: lowercase with `.template` suffix or content extension (`mqtt.json.template`, `kiosk.desktop`)
- Config: lowercase with hyphens in directory/file names (`autostart/`, `systemd/`)
- Documentation: UPPERCASE markdown (`ARCHITECTURE.md`, `STRUCTURE.md`, `README.md`)

**Directories:**

- Functional grouping: `scripts/`, `config/`, `diagnostics/`
- Sub-categories: `scripts/setup/`, `config/autostart/`, `config/systemd/`
- Lowercase with hyphens where descriptive
- Pattern: Function before context (not `config/systemd-scripts/`, but `config/systemd/` and separate `scripts/`)

**Classes:**

- PascalCase: `DisplayMQTTClient` (in `scripts/mqtt_listener.py` line 50)

**Functions/Methods:**

- snake_case in Python: `_load_config()`, `_on_connect()`, `_handle_command()`
- kebab-case in shell: `log_message()`, `ensure_apt_packages()`, `check_touchscreen_service()`

**Variables:**

- UPPERCASE constants: `TOUCHSCREEN_ID`, `FLAG_FILE`, `TOPIC_COMMAND`, `CONFIG_FILE`
- lowercase with underscores in functions: `mqtt_broker`, `service_template`, `rendered`

**Environment Variables:**

- UPPERCASE: `DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, `INSTALL_DOCKER`
- Path references: `__REPO_ROOT__`, `__MQTT_BROKER__`, `__MQTT_USERNAME__`, `__MQTT_PASSWORD__`

## Where to Add New Code

**New Feature (e.g., additional display automation):**
- Primary code: `scripts/{feature-name}.py` or `scripts/{feature-name}.sh`
- Configuration: `config/{feature-name}.json.template` if needing MQTT credentials or broker settings
- Systemd service: `config/systemd/{feature-name}.service` if running as daemon
- Bootstrap setup: Add initialization function to `scripts/setup/bootstrap.sh` (follow existing pattern: install_*, configure_*, sync_*)
- Verification: Add check function to `scripts/setup/verify.sh` (pattern: check_*, require_*)

**New Systemd Service:**
- Template file: `config/systemd/{service-name}.service`
- Rendering: Add `install_{service-name}_service()` to bootstrap.sh (lines 88-113 show pattern)
- Verification: Add `check_{service-name}()` to verify.sh (lines 70-85 show pattern)
- Remember: Use `__REPO_ROOT__` token for paths, include `After=` and `Wants=` for ordering

**New Configuration:**
- Template: `config/{config-name}.json.template` or `config/{config-name}.template`
- Rendering: Add `configure_{config-name}()` to bootstrap.sh (lines 120-156 show pattern)
- Protection: Set file permissions to 600 if containing credentials (line 154: `chmod 600`)
- Verification: Check file exists in verify.sh, warn if missing

**Python Utilities:**
- Location: `scripts/{utility-name}.py`
- Pattern: Follow structure from `display_control.py` (argument parsing) or `mqtt_listener.py` (class-based)
- Entry: `if __name__ == "__main__"` at bottom
- Imports: Type hints, standard library preferred, paho-mqtt available
- Logging: Use Python `logging` module (see mqtt_listener.py lines 40-46)

**Shell Scripts:**
- Location: `scripts/{script-name}.sh` (functions/utilities) or keep system-specific (diagnostic, recovery)
- Pattern: `set -euo pipefail` at top, two-space indentation, quote all variables
- Logging: Use `logger -t` for systemd journal, `echo` for stdout
- Bootstrap tasks: Add to bootstrap.sh main() function (lines 186-196)

**Tests:**
- When added: Create `tests/` directory with `test_*.py` or `*_test.py` per convention
- Mark in TESTING.md (to be created) with location, framework, and run commands
- Add to verify.sh if tests must pass for deployment validation

## Special Directories

**diagnostics/:**
- Purpose: Troubleshooting artifacts
- Generated: By user running `./scripts/diagnose-usb.sh [cold|warm]`
- Tracking: Git-ignored (not committed)
- Retention: Manual cleanup by user

**.planning/codebase/:**
- Purpose: Static analysis and reference documents
- Generated: By GSD codebase mapper tool (not in regular workflow)
- Tracking: Git-tracked, updated periodically
- Consumers: GSD phase planning and execution tools

**__pycache__/, *.pyc:**
- Purpose: Python bytecode cache
- Generated: Automatically by Python interpreter
- Tracking: Git-ignored
- Action: No manual intervention needed

**.git/, .gitignore:**
- Purpose: Version control metadata and exclusion rules
- Tracking: .git directory internal, .gitignore committed
- Contents of .gitignore: config/mqtt.json, __pycache__/, *.pyc, .env files, editor artifacts

---

*Structure analysis: 2026-02-11*
