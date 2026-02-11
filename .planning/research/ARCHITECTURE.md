# Architecture Research: Pi Kiosk Hardening

**Domain:** Raspberry Pi Kiosk Systems
**Researched:** 2026-02-11
**Confidence:** MEDIUM

## Standard Architecture for Hardened Pi Kiosk

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│                  User-Facing Layer                           │
│  ┌────────────────────────────────────────────────────┐     │
│  │  Chromium Browser (kiosk mode)                     │     │
│  │  - Full-screen display                             │     │
│  │  - Browser extension for idle reset                │     │
│  └───────────┬────────────────────────────────────────┘     │
│              │ (controlled by)                              │
├──────────────┴──────────────────────────────────────────────┤
│                  Control Layer                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Browser      │  │ WiFi         │  │ Hardware     │       │
│  │ Watchdog     │  │ Watchdog     │  │ Watchdog     │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                 │               │
│         └─────────────────┴─────────────────┘               │
│                           │                                 │
├───────────────────────────┴─────────────────────────────────┤
│                  Service Orchestration Layer                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              systemd                                 │    │
│  │  - Service dependencies (After/Wants/Requires)       │    │
│  │  - Auto-restart policies                             │    │
│  │  - Health monitoring (OnFailure)                     │    │
│  │  - Logging (journalctl)                              │    │
│  └─────────────────┬───────────────────────────────────┘    │
│                    │                                         │
├────────────────────┴─────────────────────────────────────────┤
│                  Integration Layer                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ MQTT Client  │  │ Display Ctl  │  │ Input Ctl    │       │
│  │ (HA bridge)  │  │ (HDMI power) │  │ (xdotool)    │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
├─────────────────────────────────────────────────────────────┤
│                  Configuration Layer                         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Centralized Config (JSON)                            │   │
│  │  - MQTT broker settings                               │   │
│  │  - Dashboard URL                                      │   │
│  │  - Watchdog intervals                                 │   │
│  │  - Auto-return timeout                                │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Typical Implementation |
|-----------|----------------|------------------------|
| Browser Kiosk | Display dashboard, handle user interaction | Chromium with --kiosk flags, extension for idle reset |
| Browser Watchdog | Detect crashes, restart browser, dismiss error dialogs | Python script supervised by systemd with Restart=on-failure |
| WiFi Watchdog | Monitor network connectivity, trigger recovery | systemd timer + bash script checking ping to gateway/DNS |
| Hardware Watchdog | Detect system freezes, automatic reboot | systemd WatchdogSec with sd_notify heartbeats |
| MQTT Client | Receive commands from Home Assistant | Python daemon with paho-mqtt, publishes availability |
| Display Control | HDMI power management | vcgencmd wrapper (Pi-specific) or CEC control |
| Config Manager | Single source of truth for all settings | JSON file loaded by all components |
| Service Orchestrator | Coordinate startup order, restart policies | systemd unit files with dependencies |

## Recommended Project Structure

Based on ecosystem patterns, move from flat structure to organized layering:

```
~/dashboard-project/
├── config/
│   ├── kiosk.json              # CENTRALIZED config (replaces mqtt.json + URL hardcoding)
│   ├── templates/              # systemd and autostart templates
│   │   ├── systemd/
│   │   │   ├── kiosk-browser.service
│   │   │   ├── browser-watchdog.service
│   │   │   ├── wifi-watchdog.service
│   │   │   ├── wifi-watchdog.timer
│   │   │   ├── mqtt-listener.service
│   │   │   └── touchscreen-check.service
│   │   └── autostart/
│   │       └── kiosk.desktop
│   └── .gitignore              # Exclude kiosk.json (contains secrets)
├── scripts/
│   ├── browser/
│   │   ├── launch.sh           # Start Chromium (current kiosk.sh)
│   │   └── watchdog.py         # Monitor browser, restart on crash
│   ├── network/
│   │   └── wifi-watchdog.sh    # Check connectivity, recover
│   ├── hardware/
│   │   ├── display_control.py  # HDMI power management (existing)
│   │   └── touchscreen-check.sh # Touchscreen detection (existing)
│   ├── integrations/
│   │   └── mqtt_listener.py    # Home Assistant bridge (existing)
│   ├── lib/
│   │   └── config.py           # Shared config loader
│   └── setup/
│       ├── bootstrap.sh        # Provision from scratch (existing)
│       └── verify.sh           # Health checks (existing)
├── extensions/
│   └── idle-reset/             # Browser extension for auto-return
│       ├── manifest.json
│       └── background.js
├── tests/
│   ├── unit/                   # Component tests with mocks
│   └── integration/            # End-to-end tests
├── .planning/                  # GSD working directory
├── readme.md
└── CLAUDE.md
```

### Structure Rationale

- **config/**: All configuration in one place. Secrets excluded from git via .gitignore
- **scripts/browser/**: Browser-specific logic isolated from other concerns
- **scripts/network/**: Network recovery isolated, can be developed/tested independently
- **scripts/lib/**: Shared utilities (config loading) prevent duplication
- **extensions/**: Browser extension for idle detection lives with code, not externally managed
- **tests/**: Tests alongside implementation, mocked for hardware dependencies

## Architectural Patterns

### Pattern 1: Centralized Configuration

**What:** Single JSON config file consumed by all components

**When to use:** Projects with multiple scripts that need consistent settings (URL, timeouts, MQTT broker, etc.)

**Trade-offs:**
- PRO: Single source of truth, easier to reconfigure
- PRO: No hardcoded values scattered across files
- CON: All components need config loading logic
- CON: Config file is a single point of failure

**Recommended structure:**
```json
{
  "dashboard": {
    "url": "http://192.168.68.75:8123",
    "idle_timeout_seconds": 300
  },
  "mqtt": {
    "broker": "192.168.68.75",
    "port": 1883,
    "username": "mqtt_user",
    "password": "secret",
    "topics": {
      "command": "dashboard/display/command",
      "status": "dashboard/display/status",
      "availability": "dashboard/display/availability"
    }
  },
  "watchdog": {
    "browser_check_interval_seconds": 30,
    "wifi_check_interval_seconds": 60,
    "wifi_ping_targets": ["8.8.8.8", "1.1.1.1"]
  }
}
```

**Implementation:**
```python
# scripts/lib/config.py
import json
from pathlib import Path
from typing import Any

CONFIG_PATH = Path.home() / "dashboard-project" / "config" / "kiosk.json"

def load_config() -> dict[str, Any]:
    with open(CONFIG_PATH) as f:
        return json.load(f)

def get_nested(config: dict, *keys: str) -> Any:
    """Safely get nested config value"""
    value = config
    for key in keys:
        value = value[key]
    return value

# Usage in scripts:
# from lib.config import load_config, get_nested
# config = load_config()
# url = get_nested(config, "dashboard", "url")
```

### Pattern 2: Browser Watchdog with Process Supervision

**What:** Python daemon that monitors Chromium process, restarts on crash, dismisses error dialogs

**When to use:** Kiosks that must stay online 24/7 without manual intervention

**Trade-offs:**
- PRO: Automatic recovery from browser crashes
- PRO: systemd handles watchdog process restart
- CON: Adds complexity versus simple autostart
- CON: Requires careful PID tracking (Chromium spawns multiple processes)

**Implementation approach:**
```python
# scripts/browser/watchdog.py (pseudo-code)
import subprocess
import time
from lib.config import load_config

config = load_config()
check_interval = config["watchdog"]["browser_check_interval_seconds"]

while True:
    if not is_chromium_running():
        log("Browser crashed, restarting...")
        launch_browser()

    dismiss_error_dialogs()  # Use xdotool to close "Aw, Snap!" dialogs

    time.sleep(check_interval)
```

**systemd service pattern:**
```ini
[Service]
Type=simple
Restart=on-failure
RestartSec=10
# Watchdog owns browser lifecycle, browser should not auto-restart separately
```

### Pattern 3: WiFi Watchdog with systemd Timer

**What:** Periodic connectivity check via ping, trigger recovery actions

**When to use:** WiFi environments with unreliable connectivity

**Trade-offs:**
- PRO: Automated network recovery
- PRO: systemd timer is more reliable than cron for boot-time scheduling
- CON: Aggressive recovery (reboot) may interrupt legitimate use
- CON: False positives if ping targets are temporarily unreachable

**Implementation:**
```bash
# scripts/network/wifi-watchdog.sh
#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/../lib/config.sh"  # Load ping targets from config

for target in "${PING_TARGETS[@]}"; do
  if ping -c 1 -W 5 "$target" &>/dev/null; then
    exit 0  # Success, network is up
  fi
done

# All ping targets failed
logger "WiFi watchdog: network unreachable, attempting recovery"
sudo systemctl restart NetworkManager
sleep 30

# Recheck
for target in "${PING_TARGETS[@]}"; do
  if ping -c 1 -W 5 "$target" &>/dev/null; then
    exit 0  # Recovery successful
  fi
done

# Still down, reboot
logger "WiFi watchdog: recovery failed, rebooting"
sudo reboot
```

**systemd timer pattern:**
```ini
# wifi-watchdog.timer
[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

# wifi-watchdog.service
[Service]
Type=oneshot
ExecStart=/path/to/wifi-watchdog.sh
```

### Pattern 4: Idle Detection via Browser Extension

**What:** Chromium extension using Idle Detection API to auto-navigate to home page

**When to use:** Public kiosks or shared displays that need to reset after inactivity

**Trade-offs:**
- PRO: Native browser integration, more reliable than external xdotool polling
- PRO: Uses web platform API designed for kiosks
- CON: Requires extension management in deployment
- CON: Idle Detection API permission prompt (can be suppressed with policy)

**Implementation:**
```javascript
// extensions/idle-reset/background.js
chrome.idle.setDetectionInterval(300);  // 5 minutes from config

chrome.idle.onStateChanged.addListener((state) => {
  if (state === 'idle') {
    chrome.tabs.query({active: true, currentWindow: true}, (tabs) => {
      const homeUrl = 'http://192.168.68.75:8123';  // From config
      if (tabs[0].url !== homeUrl) {
        chrome.tabs.update(tabs[0].id, {url: homeUrl});
      }
    });
  }
});
```

**Alternative (xdotool external watchdog):**
- Browser watchdog script also checks idle time via `xprintidle`
- If idle > threshold, send Ctrl+L, type home URL, send Enter
- Less elegant but works without extension management

### Pattern 5: systemd Service Dependencies

**What:** Use After/Wants/Requires to coordinate service startup order

**When to use:** Multiple services where some depend on others (e.g., browser needs network)

**Trade-offs:**
- PRO: Declarative ordering, systemd handles complexity
- PRO: Automatic recovery if dependencies fail
- CON: Overly strict dependencies can prevent boot
- CON: `Wants` vs `Requires` subtlety often misunderstood

**Dependency structure for this project:**
```
touchscreen-check.service (oneshot)
  ├─ After: multi-user.target
  └─ Wants: multi-user.target

wifi-watchdog.timer
  ├─ After: network-online.target
  └─ Wants: network-online.target

mqtt-listener.service
  ├─ After: network-online.target
  ├─ Wants: network-online.target
  └─ Restart: always

browser-watchdog.service
  ├─ After: graphical.target
  ├─ Wants: graphical.target
  └─ Restart: on-failure
```

**Guidance:**
- `After`: Order only (start after X, but don't fail if X fails)
- `Wants`: Soft dependency (start X, continue if X fails)
- `Requires`: Hard dependency (fail if X fails)
- For this project: Use `After` + `Wants` for network, avoid `Requires` (network might recover)

## Data Flow

### Browser Lifecycle Flow

```
Boot
  ↓
systemd starts graphical.target
  ↓
graphical.target starts browser-watchdog.service
  ↓
browser-watchdog.py loads config
  ↓
browser-watchdog.py launches Chromium via launch.sh
  ↓
Chromium loads URL from config, loads idle-reset extension
  ↓
(loop) browser-watchdog checks process health every 30s
  ↓
If crashed: browser-watchdog kills remnants, relaunches
  ↓
If idle detected: extension navigates to home URL
```

### Network Recovery Flow

```
systemd starts wifi-watchdog.timer (5 min after boot)
  ↓
Timer triggers wifi-watchdog.service every 5 minutes
  ↓
wifi-watchdog.sh pings targets from config
  ↓
All failed? Restart NetworkManager, wait 30s, recheck
  ↓
Still failed? Reboot
```

### MQTT Command Flow

```
Home Assistant publishes to dashboard/display/command
  ↓
mqtt-listener.py receives message
  ↓
mqtt-listener.py calls display_control.py on/off
  ↓
display_control.py uses vcgencmd to control HDMI
  ↓
mqtt-listener.py queries new status
  ↓
mqtt-listener.py publishes to dashboard/display/status
```

### Configuration Loading Flow

```
Script starts
  ↓
Import lib.config
  ↓
lib.config.load_config() reads kiosk.json
  ↓
Parse JSON
  ↓
Return dict to caller
  ↓
Caller uses get_nested() for safe access
```

## Scaling Considerations

Not applicable to single-device kiosk. Relevant consideration: **Deployment at scale**

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Single kiosk | Current architecture sufficient, config via git + bootstrap |
| 2-5 kiosks | Consider config management tool (Ansible), shared git repo per location |
| 10+ kiosks | Centralized management (Fleet management API), config server instead of local JSON |

## Anti-Patterns to Avoid

### Anti-Pattern 1: Hardcoded URLs and Settings

**What people do:** Scatter configuration values across multiple scripts (URL in launch.sh, MQTT broker in listener.py, timeouts in watchdog)

**Why it's wrong:** Changing one value requires editing multiple files, easy to miss updates, merge conflicts

**Do this instead:** Centralized config.json loaded by all components via shared lib

### Anti-Pattern 2: Autostart Without Supervision

**What people do:** Use `~/.config/autostart/kiosk.desktop` to launch browser directly, no monitoring

**Why it's wrong:** Browser crashes = blank screen until manual restart, no logging, no automatic recovery

**Do this instead:** Autostart launches supervisor daemon (browser-watchdog.py), supervisor manages browser lifecycle

### Anti-Pattern 3: Restart=always with No Rate Limiting

**What people do:** systemd service with `Restart=always` but no `StartLimitBurst`/`StartLimitIntervalSec`

**Why it's wrong:** Boot loop if service has persistent failure (bad config, missing dependency), system unusable

**Do this instead:**
```ini
Restart=on-failure
StartLimitBurst=5
StartLimitIntervalSec=300
# After 5 failures in 5 minutes, give up and stay failed
```

### Anti-Pattern 4: Secrets in Git

**What people do:** Commit `mqtt.json` with username/password to repository

**Why it's wrong:** Credentials exposed in git history, can't share repo publicly

**Do this instead:**
- `config/kiosk.json.template` with `__PLACEHOLDER__` tokens (committed)
- `config/kiosk.json` generated by bootstrap.sh, excluded in .gitignore
- bootstrap.sh prompts for secrets, renders template

### Anti-Pattern 5: Testing with Real Hardware

**What people do:** Run tests on actual Pi, rely on touchscreen/display being present

**Why it's wrong:** Slow, brittle, can't run on dev machine (Windows laptop), can't test edge cases

**Do this instead:** Mock hardware dependencies
```python
# tests/unit/test_display_control.py
from unittest.mock import patch, MagicMock

@patch('subprocess.run')
def test_display_on(mock_run):
    mock_run.return_value = MagicMock(returncode=0)
    result = display_control.turn_on()
    assert result == True
    mock_run.assert_called_once_with(
        ['vcgencmd', 'display_power', '1'],
        capture_output=True
    )
```

### Anti-Pattern 6: Monolithic Bootstrap Script

**What people do:** Single massive bootstrap.sh that does everything, hard to test individual steps

**Why it's wrong:** Can't re-run single step after failure, all-or-nothing, hard to debug

**Do this instead:** Idempotent functions that check before acting
```bash
install_mqtt_service() {
  if systemctl is-enabled mqtt-listener.service &>/dev/null; then
    log "MQTT service already installed, skipping"
    return 0
  fi

  # ... actual installation
}

# Each function can be run independently
```

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Home Assistant | MQTT pub/sub | Use paho-mqtt library, handle reconnection automatically |
| Home Assistant | Dashboard URL | Loaded from config, browser navigates to it |
| Network | Ping to gateway/DNS | Use standard ping utility, parse exit code |
| X11 Display Server | xdotool, xset, unclutter | For keyboard/mouse simulation, power management |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| browser-watchdog ↔ Chromium | Process spawn/kill via subprocess | PID tracking required, kill all Chromium processes on restart |
| mqtt-listener ↔ display_control | Shell invocation via subprocess | mqtt-listener calls display_control.py, parses stdout for status |
| All scripts ↔ config | File read (JSON) | Each script loads independently, no IPC needed |
| systemd ↔ services | D-Bus (implicit) | systemd manages lifecycle, scripts use exit codes to signal health |

## Build Order and Dependencies

### Phase 1: Centralized Config (Foundation)
**Build first because:** All other components depend on it

**Components:**
- Create `config/kiosk.json.template` with all settings
- Create `scripts/lib/config.py` loader
- Update bootstrap.sh to render template from user input
- Add `.gitignore` rules

**Dependencies:** None (foundation layer)

### Phase 2: WiFi Watchdog (Network Layer)
**Build second because:** Browser needs network, but watchdog is simpler than browser watchdog

**Components:**
- Create `scripts/network/wifi-watchdog.sh`
- Create systemd service + timer templates
- Update bootstrap.sh to install service

**Dependencies:** Centralized config (to load ping targets)

### Phase 3: Browser Watchdog (Control Layer)
**Build third because:** Depends on config, more complex than network watchdog

**Components:**
- Refactor `kiosk.sh` → `scripts/browser/launch.sh` (load URL from config)
- Create `scripts/browser/watchdog.py` (process supervision)
- Create systemd service template
- Update bootstrap.sh to install service

**Dependencies:** Centralized config, browser launch script

### Phase 4: Idle Detection (UX Layer)
**Build fourth because:** Depends on browser being stable

**Components:**
- Create browser extension in `extensions/idle-reset/`
- Update launch.sh to load extension via --load-extension flag
- Configure idle timeout from centralized config

**Dependencies:** Browser watchdog (needs stable browser), centralized config

### Phase 5: Integration Updates
**Build fifth because:** Existing integrations work, just need to use new config

**Components:**
- Update `mqtt_listener.py` to load from centralized config (instead of mqtt.json)
- Update `display_control.py` to load from centralized config if needed
- Remove old `config/mqtt.json.template` (now in `config/kiosk.json.template`)

**Dependencies:** Centralized config

### Phase 6: Testing Infrastructure
**Build last because:** Tests depend on understanding implementation

**Components:**
- Create `tests/unit/` with mocks for hardware
- Create `tests/integration/` for end-to-end scenarios
- Add test runner to verify.sh

**Dependencies:** All components implemented

## Sources

**Raspberry Pi Kiosk Architecture:**
- [Configure a Raspberry Pi as a kiosk display](https://reelyactive.github.io/diy/pi-kiosk/) - General architecture patterns
- [Raspberry Pi Chromium Kiosk Autostart: Complete Setup Guide & 2026 Best Practices](https://copyprogramming.com/howto/raspberry-pi-4-autostart-chromium) - Current year best practices
- [Turning a Raspberry Pi Into a Full-Screen Home Assistant Dashboard](https://rebeccamdeprey.com/blog/raspberry-pi-kiosk-mode) - Real-world implementation

**Browser Crash Recovery:**
- [Pi kiosk browser crash recovery watchdog architecture 2026 - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=330961) - Chromium crash handling patterns
- [Crash recovery on a raspberry pi - Raspberry Pi Forums](https://forums.raspberrypi.com/viewtopic.php?t=66180) - Recovery approaches

**systemd Service Coordination:**
- [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html) - Official systemd service documentation
- [Controlling a Multi-Service Application with Systemd](https://alesnosek.com/blog/2016/12/04/controlling-a-multi-service-application-with-systemd/) - Service dependency patterns
- [Set up self-healing services with systemd](https://www.redhat.com/en/blog/systemd-automate-recovery) - Restart and OnFailure patterns

**Idle Detection:**
- [What Is Idle Detection in Google Chrome?](https://www.makeuseof.com/what-is-idle-detection-chrome/) - Idle Detection API for kiosks
- [Idle Reset Extension](https://extpose.com/ext/10054) - Browser extension pattern for kiosk reset

**WiFi Watchdog:**
- [Keeping your Raspberry Pi online with watchdogs | Dries Buytaert](https://dri.es/keeping-your-raspberry-pi-online-with-watchdogs) - Network watchdog patterns
- [linux_network_watchdog GitHub](https://github.com/mytechia/linux_network_watchdog) - Network monitoring tool

**Configuration Management:**
- [From dotenv to dotenvx: Next Generation Config Management](https://dotenvx.com/blog/2024/06/24/dotenvx-next-generation-config-management.html) - Config management patterns
- [Raspberry Pi kiosk project structure](https://github.com/M1XZG/Raspberry-pi-kiosk-config) - Config/script separation

**Testing Bash Scripts:**
- [ShellSpec](https://shellspec.info/) - BDD unit testing framework for shell scripts
- [Writing Unit-Tests and Mocks for UNIX Shells](https://honeytreelabs.com/posts/writing-unit-tests-and-mocks-for-unix-shells/) - Mocking hardware dependencies
- [bash_shell_mock GitHub](https://github.com/capitalone/bash_shell_mock) - Mock framework for bash

**Python systemd Integration:**
- [Using watchdog and sd-notify functionality for systemd in Python 3](https://blog.stigok.com/2020/01/26/sd-notify-systemd-watchdog-python-3.html) - Heartbeat pattern
- [systemd-watchdog PyPI](https://pypi.org/project/systemd-watchdog/) - Python library for systemd integration

**Browser Controller:**
- [kiosk-controller GitHub](https://github.com/telus/kiosk-controller) - CLI and HTTP API to remotely control Chromium
- [pi-kiosk GitHub](https://github.com/rseedorff/pi-kiosk) - Python-based browser kiosk system

---
*Architecture research for: Raspberry Pi Kiosk Hardening*
*Researched: 2026-02-11*
