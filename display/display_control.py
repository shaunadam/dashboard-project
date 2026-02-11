#!/usr/bin/env python3
"""Minimal HDMI display power control using wlopm.

All configurable values are loaded from config.json via lib/config.py.
"""

import os
import subprocess
import sys
from pathlib import Path

# Add repo root to sys.path so lib.config is importable.
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from lib.config import get

WAYLAND_DISPLAY = get("display.wayland_display", "wayland-0")
XDG_RUNTIME_DIR = f"/run/user/{os.getuid()}"


def run_wlopm(state: str) -> None:
    """Run wlopm command to control display power."""
    subprocess.run(
        ["wlopm", f"--{state}", "*"],
        env={
            "WAYLAND_DISPLAY": WAYLAND_DISPLAY,
            "XDG_RUNTIME_DIR": XDG_RUNTIME_DIR,
        },
        check=True,
    )


def get_status() -> str:
    """Query actual display power state via wlopm."""
    try:
        result = subprocess.run(
            ["wlopm"],
            env={
                "WAYLAND_DISPLAY": WAYLAND_DISPLAY,
                "XDG_RUNTIME_DIR": XDG_RUNTIME_DIR,
            },
            capture_output=True,
            text=True,
            timeout=5,
        )
        output = result.stdout.strip().lower()
        # wlopm output format: "HDMI-A-1 on" or "HDMI-A-1 off"
        # or similar per the connected display
        if " on" in output:
            return "on"
        elif " off" in output:
            return "off"
        else:
            return "unknown"
    except (subprocess.TimeoutExpired, FileNotFoundError, subprocess.CalledProcessError):
        return "unknown"


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in ("on", "off", "status"):
        print("Usage: display_control.py {on|off|status}", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "status":
        status = get_status()
        print(f"Display is {status}")
        sys.exit(0)

    run_wlopm(command)
    # Verify the actual state after command
    actual = get_status()
    print(f"Display is {actual}")


if __name__ == "__main__":
    main()
