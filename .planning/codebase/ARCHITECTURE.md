# Architecture

**Analysis Date:** 2026-02-11

## Pattern Overview

**Overall:** Multi-process event-driven system with separate concerns for display presentation, system monitoring, and remote control integration.

**Key Characteristics:**
- Layered service architecture with systemd orchestration
- Message-driven display control via MQTT
- Independent startup and recovery mechanisms
- Bootstrap-driven configuration for reproducible deployments

## Layers

**Presentation Layer:**
- Purpose: Display Home Assistant dashboard in fullscreen kiosk mode
- Location: `scripts/kiosk.sh`
- Contains: X11 display configuration, Chromium launch flags, UI utility startup
- Depends on: X11 display server, chromium-browser, unclutter, onboard (on-screen keyboard)
- Used by: Autostart mechanism (triggered on user login via `.config/autostart/kiosk.desktop`)

**System Monitoring Layer:**
- Purpose: Detect hardware availability and perform automatic recovery
- Location: `scripts/touchscreen-check.sh`
- Contains: USB device detection, reboot logic with boot-loop prevention
- Depends on: systemd, lsusb, flag file system
- Used by: systemd service (one-shot service at `multi-user.target`)

**Display Control Layer:**
- Purpose: Execute power control commands against HDMI display
- Location: `scripts/display_control.py`
- Contains: Low-level wlopm interface to Wayland display server
- Depends on: wlopm utility, Wayland display environment variables
- Used by: MQTT listener service (subprocess call), manual testing

**Integration/Remote Control Layer:**
- Purpose: Bridge Home Assistant MQTT broker to local display control
- Location: `scripts/mqtt_listener.py`
- Contains: MQTT client lifecycle, message handling, state publishing
- Depends on: paho-mqtt library, config/mqtt.json, display_control.py
- Used by: systemd service at `multi-user.target`

**Discovery Helper Layer:**
- Purpose: Register display switch with Home Assistant MQTT discovery
- Location: `config/systemd/ha-init.py`
- Contains: MQTT discovery payload construction, retained topic publishing
- Depends on: paho-mqtt library, config/mqtt.json
- Used by: Manual setup step (not automated)

**Setup & Verification Layer:**
- Purpose: Initialize system and validate configuration post-setup
- Location: `scripts/setup/bootstrap.sh`, `scripts/setup/verify.sh`
- Contains: Package installation, template rendering, service registration, dependency validation
- Depends on: apt package manager, sudo access, file system permissions
- Used by: Initial Pi setup (user-initiated)

## Data Flow

**Boot Sequence:**

1. System powers on → systemd starts multi-user.target
2. Touchscreen detection runs (oneshot service, `touchscreen-check.service`)
   - Waits 60 seconds for hardware initialization
   - Checks for ILITEK device (222a:0001) via lsusb
   - If not found and no prior reboot attempt: sets flag, reboots
   - If found: clears flag, exits successfully
3. After touchscreen validates successfully, user login proceeds
4. Desktop environment loads, autostart trigger fires
5. Kiosk launcher executes (`scripts/kiosk.sh`)
   - Sets DISPLAY=:0 for X11 utilities
   - Hides mouse cursor (unclutter)
   - Loads on-screen keyboard (onboard)
   - Disables screen blanking (xset)
   - Launches Chromium to Home Assistant dashboard
6. MQTT listener runs as separate systemd service (`mqtt-listener.service`)
   - Connects to configured MQTT broker (config/mqtt.json)
   - Subscribes to `dashboard/display/command` topic
   - Listens for on/off/status commands from Home Assistant

**Remote Display Control Flow:**

1. Home Assistant automation publishes command to `dashboard/display/command` topic
2. MQTT listener receives message → calls `_on_message()` callback
3. Callback extracts command (on/off/status) and calls `_handle_command()`
4. Handler executes display_control.py via subprocess with command argument
5. display_control.py calls wlopm with Wayland environment setup
6. wlopm sends power command to display via Wayland protocol
7. MQTT listener publishes status to `dashboard/display/status` topic (retained)
8. Home Assistant receives status update and updates entity state

**Diagnostic Flow:**

1. User runs `scripts/diagnose-usb.sh [cold|warm]`
2. Script captures system info, USB devices, kernel logs, input device status
3. Output saved to `diagnostics/usb-diag-{boot-type}-{timestamp}.txt`
4. User compares cold vs warm boot outputs to identify enumeration issue

**State Management:**

- **Display state:** Published to MQTT (on/off/unknown), retained
- **MQTT availability:** Published to `dashboard/display/availability` (online/offline), retained for Last Will and Testament
- **Touchscreen reboot flag:** Single file at `/var/run/touchscreen-reboot-attempted` persists across soft reboots but clears on power cycles
- **Configuration state:** Templates in `config/` rendered to JSON at bootstrap time

## Key Abstractions

**DisplayMQTTClient Class:**
- Purpose: Encapsulates MQTT lifecycle and display command handling
- Location: `scripts/mqtt_listener.py` (lines 50-244)
- Pattern: Singleton client with callback-based event handling
- Provides: Connection management, message routing, status publishing, graceful shutdown

**Bootstrap Templating System:**
- Purpose: Separate configuration content from deployment logic
- Examples: `config/autostart/kiosk.desktop`, `config/systemd/*.service`, `config/mqtt.json.template`
- Pattern: Token substitution (`__REPO_ROOT__`, `__MQTT_*__`) rendered at setup time
- Allows: Repo-agnostic paths, secret management outside git, reproducible setup

**Systemd Service Orchestration:**
- Purpose: Define startup order, restart behavior, logging integration
- Services defined:
  - `touchscreen-check.service`: oneshot type, runs once at multi-user.target
  - `mqtt-listener.service`: simple type, always restart with 10-second delay
- Pattern: Declarative service definitions with lifecycle hooks

**Flag File Boot Loop Protection:**
- Purpose: Prevent infinite reboot cycles during cold boot recovery
- Location: `/var/run/touchscreen-reboot-attempted`
- Pattern: File presence indicates "reboot already attempted" state
- Behavior: Persists across soft reboots, cleared on successful detection or power cycle

## Entry Points

**Desktop Session Entry:**
- Location: `~/.config/autostart/kiosk.desktop` (rendered from `config/autostart/kiosk.desktop` template)
- Triggers: GNOME session startup (auto-login via raspi-config)
- Responsibilities: Execute kiosk.sh after desktop environment loads

**Boot-time Service Entry:**
- Location: `touchscreen-check.service` (rendered from `config/systemd/touchscreen-check.service`)
- Triggers: systemd multi-user.target (before login manager)
- Responsibilities: Detect hardware availability, trigger recovery reboot if needed

**Background Service Entry:**
- Location: `mqtt-listener.service` (rendered from `config/systemd/mqtt-listener.service`)
- Triggers: systemd multi-user.target (after network)
- Responsibilities: Maintain MQTT connection, process commands, publish state

**Manual Testing Entry:**
- Location: `scripts/display_control.py` (direct invocation or subprocess call)
- Triggers: User command or MQTT listener subprocess call
- Responsibilities: Execute single display power command

**Initial Setup Entry:**
- Location: `scripts/setup/bootstrap.sh` (user-initiated after git clone)
- Triggers: Manual user execution during Pi provisioning
- Responsibilities: Install packages, render templates, configure MQTT, enable services

**Post-Setup Validation Entry:**
- Location: `scripts/setup/verify.sh`
- Triggers: Manual user execution after bootstrap
- Responsibilities: Check all dependencies, service status, file permissions

## Error Handling

**Strategy:** Graceful degradation with logged failures. Services restart automatically, unrecoverable errors exit cleanly.

**Patterns:**

**MQTT Connection Loss:**
- Pattern: `paho.mqtt.client` with `Restart=always` in systemd
- Behavior: On disconnect, client auto-reconnects via paho callback; systemd restarts service after 10 seconds if process exits
- User impact: Remote commands queued or lost depending on MQTT broker retain settings

**Display Control Failure:**
- Pattern: Subprocess timeout (10s) and error capture in mqtt_listener.py
- Behavior: Exception logged, status published as 'unknown', listener continues running
- User impact: MQTT command fails but service remains responsive

**Touchscreen Not Detected:**
- Pattern: Boot loop protection via flag file
- Behavior: One automatic reboot, then manual intervention required with clear error message in logs
- User impact: First power-cycle takes 2-3 minutes, subsequent reboots are normal

**Configuration Missing:**
- Pattern: Validation at startup with sys.exit(1)
- Behavior: Systemd restarts service after 10 seconds, logs to journalctl
- User impact: Service unavailable until config/mqtt.json created via bootstrap

**Script Permission Issues:**
- Pattern: Caught at verify.sh, detailed guidance in issues array
- Behavior: Verification fails with list of required fixes
- User impact: Bootstrap must be re-run, or manual chmod commands executed

## Cross-Cutting Concerns

**Logging:**
- Approach: Dual logging (systemd journal + stdout) via `StandardOutput=journal` in service files
- Access: `journalctl -u {service-name} -f` for real-time logs
- Format: Python uses `logging` module with structured format; shell scripts use `logger -t` command

**Validation:**
- Approach: Bootstrap validates required packages and permissions; verify.sh checks post-setup state
- Points: Package installation, Python module imports, service enablement, file permissions, config file presence

**Authentication:**
- Approach: MQTT credentials stored in config/mqtt.json (git-ignored), username/password auth via paho-mqtt
- Protection: File permissions set to 600 (owner read/write only) by bootstrap.sh
- Rotation: Re-run bootstrap.sh to reconfigure credentials

**Environment Configuration:**
- Approach: Systemd service files use hardcoded environment (DISPLAY=:0 for kiosk.sh via autostart)
- Special handling: Display control sets WAYLAND_DISPLAY and XDG_RUNTIME_DIR dynamically based on UID
- Bootstrap supplies: MQTT broker details templated during setup

---

*Architecture analysis: 2026-02-11*
