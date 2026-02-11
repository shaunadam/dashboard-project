# Coding Conventions

**Analysis Date:** 2026-02-11

## Naming Patterns

**Files:**
- Lowercase with hyphens for shell scripts: `kiosk.sh`, `touchscreen-check.sh`, `mqtt-listener.service`
- Lowercase with underscores for Python scripts: `display_control.py`, `mqtt_listener.py`, `ha-init.py`
- Template files use `.template` suffix: `kiosk.desktop`, `mqtt.json.template`, `touchscreen-check.service`
- Service files follow systemd naming: `touchscreen-check.service`, `mqtt-listener.service`

**Functions:**
- Bash: Lowercase with underscores: `log_message()`, `require_command()`, `check_autostart()`, `install_mqtt_listener_service()`
- Python: Lowercase with underscores for functions and methods: `_load_config()`, `_setup_signal_handlers()`, `_on_connect()`, `_handle_command()`
- Private methods prefixed with underscore: `_load_config()`, `_signal_handler()`, `_publish_status()`
- Public class methods without underscore prefix: `run()`, `main()`

**Variables:**
- Bash: Uppercase for constants: `TOUCHSCREEN_ID="222a:0001"`, `FLAG_FILE="/var/run/touchscreen-reboot-attempted"`, `LOG_TAG="touchscreen-check"`
- Bash: Lowercase for local variables: `service_template`, `rendered`, `mqtt_broker`
- Python: Uppercase for module-level constants: `TOPIC_COMMAND`, `TOPIC_STATUS`, `CONFIG_FILE`, `DISPLAY_CONTROL_SCRIPT`
- Python: Lowercase for instance variables: `self.config`, `self.client`, `self.should_run`

**Types:**
- Python: Type hints used in function signatures: `def _load_config(self, config_path: Path) -> dict:`, `def _handle_command(self, command: str):`
- Python: Optional types: `Optional[mqtt.Client]`
- Python: Path objects: `config_path: Path`, `CONFIG_FILE = Path.home() / "dashboard-project"`

## Code Style

**Formatting:**
- Bash: Two-space indentation (see `bootstrap.sh` lines 26-36, `verify.sh` lines 15-23)
- Python: Four-space indentation (see `mqtt_listener.py` throughout)
- Line length: No strict limit enforced, but keep under 100 characters for readability
- Quotes: Bash uses double quotes for variables: `"${REPO_ROOT}"`, Python uses single or double quotes consistently

**Linting:**
- No formal linter configuration (no `.eslintrc`, `.flake8`, `pyproject.toml`)
- Bash style enforced through manual review and script structure
- Python follows implicit PEP 8 conventions
- Scripts use shebang declarations: `#!/bin/bash`, `#!/usr/bin/env bash`, `#!/usr/bin/env python3`

**Error Handling in Bash:**
- All bash scripts use strict mode: `set -euo pipefail` (see `touchscreen-check.sh` line 2, `bootstrap.sh` line 2, `verify.sh` line 2)
- This causes scripts to exit on error, undefined variables, or pipe failures
- Conditional logic checks command success: `if command -v "${cmd}" >/dev/null 2>&1;`
- Error messages logged before exit: `logger -t "$LOG_TAG" "$1"` in `touchscreen-check.sh` line 13-15

## Import Organization

**Bash:**
- No imports; uses standard utilities: `set`, `source`, `command -v`
- External commands used: `lsusb`, `logger`, `systemctl`, `sed`, `mktemp`

**Python:**
- Standard library imports first: `import json`, `import logging`, `import signal`, `import subprocess`, `import sys`, `import time`
- Pathlib for path handling: `from pathlib import Path`
- Type hints: `from typing import Optional`
- Third-party imports with try/except for graceful failure: `mqtt_listener.py` lines 23-27, `ha-init.py` lines 21-25
- Conditional imports for optional features: TLS support in `ha-init.py` line 111: `import ssl`

**Error Handling in Imports:**
- Optional dependencies caught with ImportError and helpful messages:
  ```python
  try:
      import paho.mqtt.client as mqtt
  except ImportError:
      print("Error: paho-mqtt not installed. Run: pip3 install paho-mqtt", file=sys.stderr)
      sys.exit(1)
  ```
  See `mqtt_listener.py` lines 23-27, `ha-init.py` lines 21-25

## Error Handling

**Shell Scripts:**
- Exit codes checked in conditionals: `if [ $# -ne 1 ]` in `diagnose-usb.sh` line 7
- Logging errors with descriptive messages before exit: `echo "Usage: $0 [cold|warm]" >&2; exit 1`
- Check if files exist before operations: `if [ ! -f "${service_template}" ];` in `bootstrap.sh` line 92
- Graceful degradation: `if ! command -v apt-get >/dev/null 2>&1; then ... return` in `bootstrap.sh` line 27-30
- Flag files used for state management: `/var/run/touchscreen-reboot-attempted` prevents boot loops in `touchscreen-check.sh`

**Python Scripts:**
- Try/except blocks for error handling: `mqtt_listener.py` lines 118-128, 132-158
- Specific exception types caught: `FileNotFoundError`, `subprocess.TimeoutExpired`, `json.JSONDecodeError`, `ValueError`
- Logging errors with context: `logger.error(f"Command failed: {result.stderr}")`
- Graceful shutdown on signals: `mqtt_listener.py` lines 80-91
- Config validation on load: `mqtt_listener.py` lines 70-78

**Error Patterns:**
- Message payloads validated: `mqtt_listener.py` lines 119-125 validates command is one of `['on', 'off', 'status']`
- Status parsing with fallback: `mqtt_listener.py` lines 178-184 parses display status with 'unknown' fallback
- Connection failures handled: `mqtt_listener.py` lines 224-226 exits if initial broker connection fails
- Subprocess timeout handling: `mqtt_listener.py` line 153-154 catches `TimeoutExpired` with 10-second timeout

## Logging

**Framework:**
- Bash: Uses `logger` command with tag parameter: `logger -t "$LOG_TAG" "$1"` (see `touchscreen-check.sh` line 13)
- Bash: Simple echo to stdout for console output: `echo "[bootstrap] $*"` in `bootstrap.sh` line 23
- Python: Uses standard `logging` module with `StreamHandler` output to stdout

**Patterns:**

**Bash logging** (see `bootstrap.sh` lines 22-24):
```bash
log() {
  echo "[bootstrap] $*"
}
```

**Python logging** (see `mqtt_listener.py` lines 40-47):
```python
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("mqtt_listener")
```

**When to Log:**
- Entry points: "Starting MQTT Display Control Listener" in `mqtt_listener.py` line 248
- Signal handling: "Received signal {signum}, shutting down gracefully..." in `mqtt_listener.py` line 87
- Connection state: "Connected to MQTT broker" in `mqtt_listener.py` line 96
- Command execution: "Received command: {command}" in `mqtt_listener.py` line 120
- Errors with context: "Failed to connect to broker: {e}" in `mqtt_listener.py` line 225

## Comments

**When to Comment:**
- High-level script purpose: docstrings at file start in `mqtt_listener.py` lines 2-11, `display_control.py` line 2
- Complex logic steps: `touchscreen-check.sh` line 27-30 explains flag file clearing
- Configuration context: `ha-init.py` lines 27-34 explains discoverable device identifiers
- TODO scenarios: Comments explain intended behavior like "Map 'unknown' -> unknown" in `ha-init.py` line 83

**Docstrings/Comments:**
- Python: Module-level docstrings with triple quotes explain purpose and MQTT topics (see `mqtt_listener.py` lines 2-11)
- Bash: Comments use `#` with descriptions: `# Touchscreen Detection and Auto-Reboot Script` in `touchscreen-check.sh` line 4
- Class docstrings in Python: `class DisplayMQTTClient:` with docstring "Manages MQTT connection and display control" in `mqtt_listener.py` line 50-51
- Function docstrings: `def _load_config(self, config_path: Path) -> dict:` with docstring "Load MQTT configuration from JSON file" in `mqtt_listener.py` line 59-60

## Function Design

**Size:**
- Most functions kept under 30 lines
- `mqtt_listener.py` longest function `_publish_current_status()` is 28 lines (167-193)
- Setup functions in `bootstrap.sh` range 5-25 lines
- Verification functions in `verify.sh` range 5-15 lines

**Parameters:**
- Bash functions typically 0-2 parameters: `log_message()` takes 1, `require_command()` takes 1
- Python methods take `self` plus 1-2 additional parameters: `_handle_command(self, command: str)`
- Config paths passed as parameters: `_load_config(self, config_path: Path)`
- Type hints consistently used in Python: `str`, `Path`, `dict`, `Optional[mqtt.Client]`

**Return Values:**
- Bash functions use exit codes (0 for success, 1 for failure)
- Python methods return typed values: `-> dict`, `-> None`
- Python uses exceptions rather than error return values for error states
- Status commands return string output: `display_control.py` lines 36, 32

## Module Design

**Exports:**
- Bash: All functions are script-local; no explicit exports except environment variables (`export DISPLAY=:0` in `kiosk.sh` line 4)
- Python: Class-based organization with public methods (`run()`, `main()`) and private methods (`_load_config()`, `_on_connect()`)
- Main entry point pattern: `if __name__ == "__main__": main()` in `mqtt_listener.py` line 260-261, `display_control.py` line 39-40

**Barrel Files:**
- Not applicable; project uses direct file imports
- `mqtt_listener.py` imported directly as systemd service
- `display_control.py` imported directly by subprocess calls

## Configuration & Constants

**Top-level Constants:**
- Module-level configuration collected at top: `mqtt_listener.py` lines 30-37 define all topics
- File paths defined once: `CONFIG_FILE`, `DISPLAY_CONTROL_SCRIPT` in `mqtt_listener.py` lines 31-32
- Device identifiers configured: `DEVICE_IDENTIFIERS` in `ha-init.py` line 28
- String literals replaced with named constants: `TOPIC_COMMAND`, `TOPIC_STATUS` used throughout instead of hardcoded strings

---

*Convention analysis: 2026-02-11*
