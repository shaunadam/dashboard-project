"""Shared configuration loader for Python scripts.

Usage:
    from lib.config import get, require

    url = get("dashboard.url")
    broker = require("mqtt.broker")
"""

import json
from pathlib import Path
from typing import Any, Optional


class ConfigError(Exception):
    """Raised when a required configuration value is missing."""


# Derive config path from this file's location (lib/ is one level below root).
CONFIG_FILE = Path(__file__).resolve().parent.parent / "config.json"

# Module-level cache for the parsed config dict.
_config_cache: Optional[dict] = None


def load_config(path: Optional[Path] = None) -> dict:
    """Load and return the full configuration dictionary.

    Results are cached so repeated calls don't re-read the file.
    Pass an explicit *path* to override the default location (useful for tests).
    """
    global _config_cache

    config_path = path or CONFIG_FILE

    if _config_cache is not None and path is None:
        return _config_cache

    if not config_path.exists():
        raise ConfigError(
            f"Configuration file not found: {config_path}\n"
            "Run setup/bootstrap.sh to generate config.json from the template."
        )

    with open(config_path, "r") as fh:
        data = json.load(fh)

    if path is None:
        _config_cache = data

    return data


def get(key_path: str, default: Any = None) -> Any:
    """Navigate nested config keys using dot-notation.

    Example:
        get("mqtt.broker")          -> value or None
        get("mqtt.port", 1883)      -> value or 1883
    """
    config = load_config()
    keys = key_path.split(".")
    value = config
    for key in keys:
        if isinstance(value, dict) and key in value:
            value = value[key]
        else:
            return default
    return value


def require(key_path: str) -> Any:
    """Navigate nested config keys, raising ConfigError if missing or None."""
    value = get(key_path)
    if value is None:
        raise ConfigError(
            f"Required config value missing: {key_path}\n"
            f"Check {CONFIG_FILE} and ensure the value is set."
        )
    return value
