"""Shared configuration loader for Python scripts.

Configuration is split across two files, both at the repo root:
    config.json   - tracked in git. Everything that is not a secret.
    secrets.json  - git-ignored, chmod 600. Credentials only.
They are deep-merged on load (secrets win), so callers just ask for a
dot-path and never care which file a value came from.

Usage:
    from lib.config import get, require

    url = get("dashboard.url")
    password = require("mqtt.password")
"""

import json
from pathlib import Path
from typing import Any, Optional


class ConfigError(Exception):
    """Raised when a required configuration value is missing."""


# Derive config paths from this file's location (lib/ is one level below root).
REPO_ROOT = Path(__file__).resolve().parent.parent
CONFIG_FILE = REPO_ROOT / "config.json"
SECRETS_FILE = REPO_ROOT / "secrets.json"

# Module-level cache for the merged config dict.
_config_cache: Optional[dict] = None


def _deep_merge(base: dict, overlay: dict) -> dict:
    """Return *base* with *overlay* merged in, recursing into nested dicts.

    Mirrors jq's `*` operator, which lib/config.sh uses for the same job.
    """
    merged = dict(base)
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def _read_json(path: Path, hint: str) -> dict:
    if not path.exists():
        raise ConfigError(f"Configuration file not found: {path}\n{hint}")
    with open(path, "r") as fh:
        return json.load(fh)


def load_config(
    path: Optional[Path] = None,
    secrets_path: Optional[Path] = None,
) -> dict:
    """Load, merge and return the full configuration dictionary.

    Results are cached so repeated calls don't re-read the files. Pass
    explicit paths to override the default locations (useful for tests);
    overridden loads are never cached.
    """
    global _config_cache

    use_defaults = path is None and secrets_path is None

    if _config_cache is not None and use_defaults:
        return _config_cache

    config = _read_json(
        path or CONFIG_FILE,
        "config.json is tracked in git — check out the repo again.",
    )
    secrets = _read_json(
        secrets_path or SECRETS_FILE,
        "Create it with setup/bootstrap.sh, setup/migrate-secrets.sh, "
        "or setup/config-restore.sh <backup.json>.",
    )

    data = _deep_merge(config, secrets)

    if use_defaults:
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
            f"Check {CONFIG_FILE} and {SECRETS_FILE} and ensure the value is set."
        )
    return value
