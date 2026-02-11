#!/usr/bin/env python3
"""
Publish Home Assistant MQTT Discovery config for:
- switch.dashboard_display  (on/off via dashboard/display/command)
- button.dashboard_display_refresh_status (press -> 'status' command)

Assumes your running service already publishes:
  availability: dashboard/display/availability  (online|offline)
  status:       dashboard/display/status         (on|off|unknown)

Reads broker settings from config.json via lib/config.py.
"""

import json
import sys
import time
from pathlib import Path

# Add repo root to sys.path so lib.config is importable.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from lib.config import get, require

try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("Error: paho-mqtt not installed. Run: pip3 install paho-mqtt", file=sys.stderr)
    sys.exit(1)

# ---------- Adjust if you want multiple dashboards ----------
DEVICE_IDENTIFIERS = ["raspi-dashboard-1"]  # must match across entities to group as one device
DISCOVERY_PREFIX = "homeassistant"          # default HA discovery prefix
NODE_NAME = "Raspberry Pi Dashboard"        # device name in HA
MODEL = "Pi + HDMI Display"
MANUFACTURER = "Raspberry Pi"
UNIQUE_SWITCH = "dashboard_display_switch"
UNIQUE_BUTTON = "dashboard_display_status_button"

# Topics used by the listener (loaded from config).
TOPIC_COMMAND = get("mqtt.topics.command", "dashboard/display/command")
TOPIC_STATUS = get("mqtt.topics.status", "dashboard/display/status")
TOPIC_AVAIL = get("mqtt.topics.availability", "dashboard/display/availability")


def on_connect(client, userdata, flags, rc):
    if rc != 0:
        print(f"Failed to connect, rc={rc}", file=sys.stderr)


def main():
    # Load MQTT broker config from centralized config.json.
    broker = require("mqtt.broker")
    port = get("mqtt.port", 1883)
    username = get("mqtt.username")
    password = get("mqtt.password")

    # Prepare payloads
    device_block = {
        "identifiers": DEVICE_IDENTIFIERS,
        "name": NODE_NAME,
        "manufacturer": MANUFACTURER,
        "model": MODEL,
    }

    switch_payload = {
        "name": "Dashboard Display",
        "unique_id": UNIQUE_SWITCH,
        "command_topic": TOPIC_COMMAND,
        "state_topic": TOPIC_STATUS,
        "availability_topic": TOPIC_AVAIL,
        "payload_on": "on",
        "payload_off": "off",
        "state_on": "on",
        "state_off": "off",
        # Map 'unknown' -> unknown so HA shows it correctly
        "value_template": "{% if value == 'on' %}on{% elif value == 'off' %}off{% else %}unknown{% endif %}",
        "device": device_block,
    }

    button_payload = {
        "name": "Dashboard Display: Refresh Status",
        "unique_id": UNIQUE_BUTTON,
        "command_topic": TOPIC_COMMAND,
        "payload_press": "status",
        "availability_topic": TOPIC_AVAIL,
        "device": device_block,
    }

    # Discovery topics (retain=True so HA picks them up anytime)
    topic_switch_cfg = f"{DISCOVERY_PREFIX}/switch/dashboard_display/config"
    topic_button_cfg = f"{DISCOVERY_PREFIX}/button/dashboard_display_status/config"

    # Connect
    client = mqtt.Client(client_id="dashboard-display-discovery-pub", clean_session=True)
    client.on_connect = on_connect

    # Auth
    if username:
        client.username_pw_set(username, password or "")

    client.connect(broker, int(port), keepalive=30)

    client.loop_start()

    # Publish retained configs
    # Note: we publish JSON strings; HA will retain and create entities
    res1 = client.publish(topic_switch_cfg, json.dumps(switch_payload), qos=1, retain=True)
    res1.wait_for_publish()

    res2 = client.publish(topic_button_cfg, json.dumps(button_payload), qos=1, retain=True)
    res2.wait_for_publish()

    # Give the network loop a moment to flush
    time.sleep(0.5)

    client.loop_stop()
    client.disconnect()

    print("Published HA discovery for switch + button (retained).")
    print(f"- {topic_switch_cfg}")
    print(f"- {topic_button_cfg}")
    print("If entities don't appear, verify the MQTT integration discovery prefix and restart Home Assistant.")


if __name__ == "__main__":
    main()
