# Testing Patterns

**Analysis Date:** 2026-02-11

## Test Framework

**Runner:**
- No automated test runner detected (no pytest, jest, vitest configurations)
- Testing relies on manual verification and shell-based smoke tests
- Verification script: `scripts/setup/verify.sh` serves as central smoke test suite

**Assertion Library:**
- Bash: Uses built-in `[` test constructs and command exit codes
- Python: No unit test framework; validation done in main execution paths

**Run Commands:**
```bash
./scripts/setup/verify.sh              # Run all verification checks
./scripts/kiosk.sh                     # Manual test of browser startup
python3 scripts/mqtt_listener.py       # Manual test of MQTT listener
python3 scripts/display_control.py on  # Manual test of display control
./scripts/touchscreen-check.sh         # Manual test of touchscreen detection
```

## Test File Organization

**Location:**
- Tests integrated into operational scripts (not separated)
- Verification logic in `scripts/setup/verify.sh` (main test suite)
- Diagnostic/debug scripts: `scripts/diagnose-usb.sh`, `scripts/usb-rescan.sh`

**Naming:**
- Verification script: `verify.sh` (not `verify.test.sh`)
- Diagnostic scripts: `diagnose-usb.sh`, `usb-rescan.sh`

**Structure:**
```
scripts/
├── kiosk.sh                      # Script with manual test capability
├── touchscreen-check.sh          # Script with integrated health checks
├── mqtt_listener.py              # Service with health checks (config validation)
├── display_control.py            # CLI tool with argument validation
├── diagnose-usb.sh               # Diagnostic data collector
├── usb-rescan.sh                 # USB recovery with status verification
└── setup/
    ├── bootstrap.sh              # Provisioning with error handling
    └── verify.sh                 # Comprehensive verification suite
```

## Test Structure

**Verification Suite** (`scripts/setup/verify.sh`):

The `verify.sh` script (lines 1-142) follows this pattern:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

issues=()  # Array to collect failed checks

log() {
  echo "[verify] $*"
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    issues+=("Missing command: ${cmd}")
  else
    log "Found command: ${cmd}"
  fi
}

# ... more check functions ...

main() {
  log "Starting verification..."
  require_command chromium-browser
  require_command unclutter
  # ... more checks ...

  if [[ ${#issues[@]} -eq 0 ]]; then
    log "All checks passed."
    exit 0
  fi

  log "Encountered issues:"
  for issue in "${issues[@]}"; do
    echo " - ${issue}"
  done
  exit 1
}

main "$@"
```

**Key Features:**
- Accumulates issues in array: `issues+=("Missing command: ${cmd}")`
- Separates success messages from failures
- Comprehensive checks for commands, Python modules, systemd services, file permissions
- Returns proper exit code (0 for success, 1 for failure)

## Manual Testing Patterns

**Script Testing:**

**Bash scripts** tested manually:
```bash
# Test kiosk startup
./scripts/kiosk.sh

# Test touchscreen detection (CAUTION: triggers reboot)
./scripts/touchscreen-check.sh

# Test USB recovery
./scripts/usb-rescan.sh

# Collect diagnostics for debugging
./scripts/diagnose-usb.sh cold    # After power cycle
./scripts/diagnose-usb.sh warm    # After warm reboot
```

**Python scripts** tested as CLI tools:
```bash
# Test display control (requires wlopm and Wayland)
python3 scripts/display_control.py on
python3 scripts/display_control.py off
python3 scripts/display_control.py status

# Test MQTT listener (runs as daemon)
python3 scripts/mqtt_listener.py    # Starts listening (Ctrl+C to stop)
```

**Configuration Testing:**

Bootstrap validation (in `bootstrap.sh`):
- File existence checks before operations: `if [ ! -f "${service_template}" ];` (line 92)
- Template rendering with temporary files: `rendered="$(mktemp)"` (line 101)
- File comparison to detect changes: `if cmp -s "${rendered}" "${AUTOSTART_DEST}"` (line 71)
- Permission verification: `if [[ -x "${REPO_ROOT}/scripts/kiosk.sh" ]]` in `verify.sh` (line 63)

**Systemd Service Verification:**

From `verify.sh` (lines 70-108):
```bash
check_touchscreen_service() {
  if [[ ! -f "${REPO_ROOT}/scripts/touchscreen-check.sh" ]]; then
    issues+=("touchscreen-check.sh not found")
    return
  fi

  if [[ ! -x "${REPO_ROOT}/scripts/touchscreen-check.sh" ]]; then
    issues+=("touchscreen-check.sh is not executable")
  fi

  if systemctl is-enabled touchscreen-check.service >/dev/null 2>&1; then
    log "touchscreen-check.service is enabled."
  else
    issues+=("touchscreen-check.service is not enabled...")
  fi
}
```

Checks performed:
- Script file existence
- Script executable bit (`-x` flag)
- Systemd service enabled status (`systemctl is-enabled`)
- Config files created by bootstrap
- Python module availability (`python3 -c "import module"`)

## Hardware Integration Testing

**Touchscreen Auto-Recovery:**

From `touchscreen-check.sh`:
1. Wait for system stabilization: `sleep "${WAIT_TIME}"` (60 seconds)
2. USB device detection: `lsusb | grep -q "$TOUCHSCREEN_ID"` (line 23)
3. State management with flag file: `/var/run/touchscreen-reboot-attempted`
4. Single automatic reboot: `systemctl reboot` (line 50)
5. Boot loop prevention: Checks flag before rebooting (lines 39-43)

**USB Diagnostics Collection:**

From `diagnose-usb.sh`:
Captures comprehensive system state for debugging:
- System info: `uname -a`, `uptime`
- USB devices: `lsusb`, `lsusb -v`
- Input devices: `/dev/input/` listing
- Kernel logs: `dmesg` filtered for USB/touchscreen keywords
- Loaded modules: `lsmod` for USB/HID/input drivers

Usage pattern:
```bash
./scripts/diagnose-usb.sh cold   # Cold boot (power cycle) diagnostics
./scripts/diagnose-usb.sh warm   # Warm boot (reboot) diagnostics
# Compare cold vs warm to identify initialization issues
```

## Python MQTT Testing

**Configuration Validation** (`mqtt_listener.py` lines 59-78):

```python
def _load_config(self, config_path: Path) -> dict:
    """Load MQTT configuration from JSON file"""
    if not config_path.exists():
        logger.error(f"Config file not found: {config_path}")
        logger.error("Create config file with: broker, port, username, password")
        sys.exit(1)

    try:
        with open(config_path, 'r') as f:
            config = json.load(f)

        # Validate required fields
        required = ['broker', 'port']
        if not all(k in config for k in required):
            raise ValueError(f"Config must contain: {required}")

        return config
    except (json.JSONDecodeError, ValueError) as e:
        logger.error(f"Invalid config file: {e}")
        sys.exit(1)
```

Tests performed:
- File existence
- Valid JSON parsing
- Required field presence (`broker`, `port`)
- Helpful error messages

**Command Validation** (`mqtt_listener.py` lines 118-128):

```python
def _on_message(self, client, userdata, msg):
    """Callback when message received on subscribed topic"""
    try:
        command = msg.payload.decode('utf-8').strip().lower()
        logger.info(f"Received command: {command}")

        if command in ['on', 'off', 'status']:
            self._handle_command(command)
        else:
            logger.warning(f"Unknown command: {command}")

    except Exception as e:
        logger.error(f"Error processing message: {e}")
```

Validates:
- Message decoding success
- Command is one of allowed values: `['on', 'off', 'status']`
- Graceful error handling for malformed messages

**Subprocess Execution** (`mqtt_listener.py` lines 134-158):

```python
def _handle_command(self, command: str):
    """Execute display control command and publish status"""
    try:
        # Run display_control.py with the command
        result = subprocess.run(
            ['python3', str(DISPLAY_CONTROL_SCRIPT), command],
            capture_output=True,
            text=True,
            timeout=10
        )

        if result.returncode == 0:
            logger.info(f"Command '{command}' executed successfully")
            # ... publish status ...
        else:
            logger.error(f"Command failed: {result.stderr}")

    except subprocess.TimeoutExpired:
        logger.error(f"Command '{command}' timed out")
    except FileNotFoundError:
        logger.error(f"Display control script not found: {DISPLAY_CONTROL_SCRIPT}")
    except Exception as e:
        logger.error(f"Error executing command: {e}")
```

Tests executed:
- Script file existence before execution
- 10-second timeout on subprocess calls
- Exit code checking
- Stderr capture for error messages
- Specific exception handling (TimeoutExpired, FileNotFoundError)

## Error Scenario Testing

**Connection Failure Handling** (`mqtt_listener.py` lines 218-226):

```python
try:
    self.client.connect(
        self.config['broker'],
        self.config['port'],
        keepalive=60
    )
except Exception as e:
    logger.error(f"Failed to connect to broker: {e}")
    sys.exit(1)
```

Exit on broker connection failure; no retry loop.

**Status Parsing with Fallback** (`mqtt_listener.py` lines 176-189):

```python
if result.returncode == 0:
    # Parse output for status (display_control.py outputs "Display is on/off")
    output = result.stdout.strip().lower()
    if 'is on' in output:
        status = 'on'
    elif 'is off' in output:
        status = 'off'
    else:
        status = 'unknown'

    self._publish_status(status)
else:
    logger.error(f"Failed to get status: {result.stderr}")
    self._publish_status('unknown')
```

Handles parsing uncertainty with 'unknown' state.

**Signal Handling** (`mqtt_listener.py` lines 80-91):

```python
def _setup_signal_handlers(self):
    """Handle graceful shutdown on SIGTERM/SIGINT"""
    signal.signal(signal.SIGTERM, self._signal_handler)
    signal.signal(signal.SIGINT, self._signal_handler)

def _signal_handler(self, signum, frame):
    """Handle shutdown signals"""
    logger.info(f"Received signal {signum}, shutting down gracefully...")
    self.should_run = False
    if self.client:
        self.client.loop_stop()
        self.client.disconnect()
```

Tests shutdown behavior via SIGTERM (systemd stop) and SIGINT (Ctrl+C).

## Test Data & Fixtures

**Configuration Files:**

Template files used as test fixtures:
- `config/mqtt.json.template` - Test MQTT config rendering in bootstrap
- `config/autostart/kiosk.desktop` - Test template substitution
- `config/systemd/touchscreen-check.service` - Test systemd service installation
- `config/systemd/mqtt-listener.service` - Test systemd service installation

**Test Constants:**

Hardcoded test values in scripts:
- `TOUCHSCREEN_ID="222a:0001"` in `touchscreen-check.sh` - USB device ID to detect
- `HUB_PATH="/sys/bus/usb/devices/1-1"` in `usb-rescan.sh` - Hardware path for testing
- Mock MQTT topics in `ha-init.py` lines 37-39

## Coverage

**Requirements:**
- No formal coverage metrics enforced
- Manual verification of critical paths

**Test Paths:**

**Critical Paths Covered:**
1. Touchscreen detection and auto-recovery (touchscreen-check.sh)
2. MQTT broker connection and message handling (mqtt_listener.py)
3. Display control execution (display_control.py)
4. System provisioning and configuration (bootstrap.sh)
5. System state verification (verify.sh)

**Gaps:**
- No automated tests for display control actual hardware interaction (wlopm command)
- No automated tests for Chromium browser startup (manual verification only)
- No tests for edge cases in MQTT message parsing
- No tests for long-running MQTT listener reconnection behavior

---

*Testing analysis: 2026-02-11*
