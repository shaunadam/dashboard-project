#!/usr/bin/env python3
"""Minimal HDMI display power control using wlopm."""

import os
import subprocess
import sys

WAYLAND_DISPLAY = "wayland-0"
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


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in ("on", "off", "status"):
        print("Usage: display_control.py {on|off|status}", file=sys.stderr)
        sys.exit(1)

    command = sys.argv[1]

    if command == "status":
        print("Status check not implemented yet")
        sys.exit(0)

    run_wlopm(command)
    print(f"Display turned {command}")


if __name__ == "__main__":
    main()
