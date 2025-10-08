#!/usr/bin/env python3
"""Utilities for powering an HDMI display on/off and running a simple schedule."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, time as dt_time
from pathlib import Path
from typing import Optional, Sequence

VCGENCMD_DISPLAY_IDS: Sequence[str] = ("0", "1", "2", "3", "7")


def _build_env() -> dict[str, str]:
    env = os.environ.copy()
    env.setdefault("DISPLAY", ":0")
    if "XAUTHORITY" not in env:
        xauth = Path.home() / ".Xauthority"
        if xauth.exists():
            env["XAUTHORITY"] = str(xauth)
    return env


DEFAULT_ENV = _build_env()


def run_command(
    cmd: Sequence[str], *, capture_output: bool = False, check: bool = True
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture_output,
        env=DEFAULT_ENV,
    )


def _wake_x_session() -> None:
    xset = shutil.which("xset")
    if not xset:
        return
    run_command([xset, "dpms", "force", "on"], check=False)


def _suspend_x_session() -> None:
    xset = shutil.which("xset")
    if not xset:
        return
    run_command([xset, "dpms", "force", "off"], check=False)


@dataclass(frozen=True)
class Backend:
    name: str
    command: str

    def set_power(self, on: bool) -> None:
        if on:
            _wake_x_session()
        else:
            _suspend_x_session()

        if self.name == "vcgencmd":
            power = "1" if on else "0"
            run_command([self.command, "display_power", power], check=False)
            for display_id in VCGENCMD_DISPLAY_IDS:
                run_command(
                    [self.command, "display_power", power, display_id], check=False
                )
            return

        if self.name == "tvservice":
            run_command([self.command, "-p" if on else "-o"], check=False)
            return

        raise RuntimeError(f"Unsupported backend: {self.name}")

    def read_power(self) -> Optional[bool]:
        if self.name == "vcgencmd":
            states = []
            for display_id in (None, *VCGENCMD_DISPLAY_IDS):
                cmd = [self.command, "display_power"]
                if display_id is not None:
                    cmd.append(display_id)
                result = run_command(cmd, capture_output=True, check=False)
                if result.returncode != 0 or not result.stdout:
                    continue
                if "display_power=1" in result.stdout:
                    states.append(True)
                elif "display_power=0" in result.stdout:
                    states.append(False)
            if states:
                return any(states)
            return None

        if self.name == "tvservice":
            result = run_command([self.command, "-s"], capture_output=True, check=False)
            if "TV is off" in result.stdout:
                return False
            if "HDMI" in result.stdout or "DVI" in result.stdout:
                return True
            return None

        return None


def get_backend() -> Backend:
    vcgencmd = shutil.which("vcgencmd")
    if vcgencmd:
        return Backend("vcgencmd", vcgencmd)

    tvservice = shutil.which("tvservice")
    if tvservice:
        return Backend("tvservice", tvservice)

    raise SystemExit(
        "No supported display control command found. Install vcgencmd (default on Raspberry Pi) or tvservice."
    )


def parse_time(value: str) -> dt_time:
    try:
        return dt_time.fromisoformat(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(
            f"Invalid time '{value}'. Use HH:MM (24-hour)."
        ) from exc


def should_be_on(now: dt_time, on_time: dt_time, off_time: dt_time) -> bool:
    if on_time == off_time:
        return True

    if on_time < off_time:
        return on_time <= now < off_time

    return not (off_time <= now < on_time)


def cmd_on(args: argparse.Namespace) -> None:
    backend = get_backend()
    backend.set_power(True)


def cmd_off(args: argparse.Namespace) -> None:
    backend = get_backend()
    backend.set_power(False)


def cmd_status(args: argparse.Namespace) -> None:
    backend = get_backend()
    state = backend.read_power()
    if state is None:
        print("Unknown display state", file=sys.stderr)
        raise SystemExit(3)
    print("on" if state else "off")


def cmd_schedule(args: argparse.Namespace) -> None:
    backend = get_backend()
    on_time = parse_time(args.on_time)
    off_time = parse_time(args.off_time)
    interval = args.interval
    last_state: Optional[bool] = None

    try:
        while True:
            now = datetime.now().time()
            desired = should_be_on(now, on_time, off_time)
            if last_state is None or desired != last_state:
                backend.set_power(desired)
                last_state = desired
            time.sleep(interval)
    except KeyboardInterrupt:
        pass


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Control the dashboard HDMI display power",
    )
    subparsers = parser.add_subparsers(required=True)

    on_parser = subparsers.add_parser("on", help="turn the display on")
    on_parser.set_defaults(func=cmd_on)

    off_parser = subparsers.add_parser("off", help="turn the display off")
    off_parser.set_defaults(func=cmd_off)

    status_parser = subparsers.add_parser("status", help="print current power state")
    status_parser.set_defaults(func=cmd_status)

    schedule_parser = subparsers.add_parser("schedule", help="loop to enforce an on/off schedule")
    schedule_parser.add_argument(
        "--on-time", default="07:00", help="HH:MM when the display should power on (default 07:00)"
    )
    schedule_parser.add_argument(
        "--off-time", default="22:00", help="HH:MM when the display should power off (default 22:00)"
    )
    schedule_parser.add_argument(
        "--interval",
        type=int,
        default=60,
        help="seconds between state checks (default 60)",
    )
    schedule_parser.set_defaults(func=cmd_schedule)

    return parser


def main(argv: Optional[list[str]] = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    main()
