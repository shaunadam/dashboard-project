#!/usr/bin/env python3
"""
MQTT Listener for Display Control

Subscribes to MQTT topics to control the HDMI display and publishes status updates.
Designed to run as a systemd service for continuous operation.

Topics:
  - dashboard/display/command (subscribe): Receives "on", "off", "status" commands
  - dashboard/display/status (publish): Current state "on", "off", "unknown"
  - dashboard/display/availability (publish): "online" or "offline"
"""

import json
import logging
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Optional

try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("Error: paho-mqtt not installed. Run: pip3 install paho-mqtt", file=sys.stderr)
    sys.exit(1)


# Configuration
CONFIG_FILE = Path.home() / "dashboard-project" / "config" / "mqtt.json"
DISPLAY_CONTROL_SCRIPT = Path.home() / "dashboard-project" / "scripts" / "display_control.py"

# MQTT Topics
TOPIC_COMMAND = "dashboard/display/command"
TOPIC_STATUS = "dashboard/display/status"
TOPIC_AVAILABILITY = "dashboard/display/availability"

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

    def __init__(self, config_path: Path):
        self.config = self._load_config(config_path)
        self.client: Optional[mqtt.Client] = None
        self.should_run = True
        self._setup_signal_handlers()

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
            client.subscribe(TOPIC_COMMAND)
            logger.info(f"Subscribed to {TOPIC_COMMAND}")

            # Publish availability
            client.publish(TOPIC_AVAILABILITY, "online", qos=1, retain=True)

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
            self.client.publish(TOPIC_STATUS, status, qos=1, retain=True)
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
        self.client = mqtt.Client(client_id="dashboard-display-pi", clean_session=False)

        # Set up callbacks
        self.client.on_connect = self._on_connect
        self.client.on_disconnect = self._on_disconnect
        self.client.on_message = self._on_message

        # Set Last Will and Testament (sent when client disconnects unexpectedly)
        self.client.will_set(TOPIC_AVAILABILITY, "offline", qos=1, retain=True)

        # Set username/password if provided
        if 'username' in self.config and 'password' in self.config:
            self.client.username_pw_set(
                self.config['username'],
                self.config.get('password', '')
            )

        # Connect to broker
        logger.info(f"Connecting to MQTT broker at {self.config['broker']}:{self.config['port']}")

        try:
            self.client.connect(
                self.config['broker'],
                self.config['port'],
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
                self.client.publish(TOPIC_AVAILABILITY, "offline", qos=1, retain=True)
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
    client = DisplayMQTTClient(CONFIG_FILE)
    client.run()


if __name__ == "__main__":
    main()
