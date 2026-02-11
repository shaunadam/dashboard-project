#!/usr/bin/env python3
"""
MQTT Listener for Display Control

Subscribes to MQTT topics to control the HDMI display and publishes status updates.
Designed to run as a systemd service for continuous operation.

All configurable values (broker, credentials, topics) are loaded from config.json
via lib/config.py.
"""

import logging
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

# Add repo root to sys.path so lib.config is importable.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from lib.config import get, require

try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("Error: paho-mqtt not installed. Run: pip3 install paho-mqtt", file=sys.stderr)
    sys.exit(1)

# Display control script path (resolved from repo root).
DISPLAY_CONTROL_SCRIPT = REPO_ROOT / "display" / "display_control.py"

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger("mqtt_listener")


class DisplayMQTTClient:
    """Manages MQTT connection and display control"""

    def __init__(self):
        # Load all MQTT settings from centralized config.
        self.mqtt_config = {
            "broker": require("mqtt.broker"),
            "port": get("mqtt.port", 1883),
            "username": get("mqtt.username"),
            "password": get("mqtt.password"),
        }

        # Load MQTT topics from config (with sensible defaults).
        self.topic_command = get("mqtt.topics.command", "dashboard/display/command")
        self.topic_status = get("mqtt.topics.status", "dashboard/display/status")
        self.topic_availability = get("mqtt.topics.availability", "dashboard/display/availability")

        # Client identity.
        self.client_id = get("mqtt.client_id", "dashboard-display-pi")

        # Heartbeat interval (read for Plan 03 to use; not implemented yet).
        self.heartbeat_interval = get("mqtt.heartbeat_interval_seconds", 60)

        self.client: Optional[mqtt.Client] = None
        self.should_run = True
        self._setup_signal_handlers()

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

    def _on_connect(self, client, userdata, flags, rc):
        """Callback when connected to MQTT broker"""
        if rc == 0:
            logger.info("Connected to MQTT broker")
            # Subscribe to command topic
            client.subscribe(self.topic_command)
            logger.info(f"Subscribed to {self.topic_command}")

            # Publish availability
            client.publish(self.topic_availability, "online", qos=1, retain=True)

            # Publish initial status
            self._publish_current_status()
        else:
            logger.error(f"Failed to connect, return code {rc}")

    def _on_disconnect(self, client, userdata, rc):
        """Callback when disconnected from broker"""
        if rc != 0:
            logger.warning(f"Unexpected disconnect (code {rc}), will attempt reconnect")
        else:
            logger.info("Disconnected from MQTT broker")

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

                # For 'on' and 'off', publish the new status immediately
                if command in ['on', 'off']:
                    self._publish_status(command)
                # For 'status', query and publish actual status
                elif command == 'status':
                    self._publish_current_status()
            else:
                logger.error(f"Command failed: {result.stderr}")

        except subprocess.TimeoutExpired:
            logger.error(f"Command '{command}' timed out")
        except FileNotFoundError:
            logger.error(f"Display control script not found: {DISPLAY_CONTROL_SCRIPT}")
        except Exception as e:
            logger.error(f"Error executing command: {e}")

    def _publish_status(self, status: str):
        """Publish display status to MQTT"""
        if self.client and self.client.is_connected():
            self.client.publish(self.topic_status, status, qos=1, retain=True)
            logger.info(f"Published status: {status}")

    def _publish_current_status(self):
        """Query current display status and publish it"""
        try:
            result = subprocess.run(
                ['python3', str(DISPLAY_CONTROL_SCRIPT), 'status'],
                capture_output=True,
                text=True,
                timeout=10
            )

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

        except Exception as e:
            logger.error(f"Error getting status: {e}")
            self._publish_status('unknown')

    def run(self):
        """Main loop - connect to broker and start listening"""
        # Initialize MQTT client
        self.client = mqtt.Client(client_id=self.client_id, clean_session=False)

        # Set up callbacks
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.client.on_message = self._on_message

        # Set Last Will and Testament (sent when client disconnects unexpectedly)
        self.client.will_set(self.topic_availability, "offline", qos=1, retain=True)

        # Set username/password if provided
        if self.mqtt_config.get('username') and self.mqtt_config.get('password'):
            self.client.username_pw_set(
                self.mqtt_config['username'],
                self.mqtt_config.get('password', '')
            )

        # Connect to broker
        logger.info(f"Connecting to MQTT broker at {self.mqtt_config['broker']}:{self.mqtt_config['port']}")

        try:
            self.client.connect(
                self.mqtt_config['broker'],
                self.mqtt_config['port'],
                keepalive=60
            )
        except Exception as e:
            logger.error(f"Failed to connect to broker: {e}")
            sys.exit(1)

        # Start the network loop
        self.client.loop_start()

        # Keep running until shutdown signal
        try:
            while self.should_run:
                time.sleep(1)
        except KeyboardInterrupt:
            logger.info("Keyboard interrupt received")
        finally:
            # Clean shutdown
            if self.client:
                self.client.publish(self.topic_availability, "offline", qos=1, retain=True)
                self.client.loop_stop()
                self.client.disconnect()
            logger.info("Shutdown complete")


def main():
    """Entry point"""
    logger.info("Starting MQTT Display Control Listener")

    # Verify display control script exists
    if not DISPLAY_CONTROL_SCRIPT.exists():
        logger.error(f"Display control script not found: {DISPLAY_CONTROL_SCRIPT}")
        sys.exit(1)

    # Create and run client
    client = DisplayMQTTClient()
    client.run()


if __name__ == "__main__":
    main()
