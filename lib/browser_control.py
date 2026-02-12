#!/usr/bin/env python3
"""Browser control via Chrome DevTools Protocol (CDP).

Navigates Chromium to a URL using the remote debugging port.
Requires Chromium to be launched with --remote-debugging-port=9222.

Usage:
    python3 lib/browser_control.py navigate <url>

Dependencies:
    python3-websocket (apt package, provides websocket-client)
"""

import json
import sys
import urllib.request
import urllib.error

try:
    import websocket
except ImportError:
    print(
        "ERROR: websocket-client not installed.\n"
        "Install with: sudo apt-get install -y python3-websocket",
        file=sys.stderr,
    )
    sys.exit(1)

CDP_PORT = 9222
CDP_HOST = "localhost"


def get_page_ws_url() -> str:
    """Get the WebSocket debugger URL for the first browser tab."""
    url = f"http://{CDP_HOST}:{CDP_PORT}/json"
    try:
        with urllib.request.urlopen(url, timeout=5) as resp:
            pages = json.loads(resp.read().decode())
    except (urllib.error.URLError, ConnectionRefusedError, OSError) as exc:
        raise RuntimeError(
            f"Cannot reach Chromium debug port at {CDP_HOST}:{CDP_PORT}. "
            "Is Chromium running with --remote-debugging-port=9222?"
        ) from exc

    if not pages:
        raise RuntimeError("No browser tabs found via CDP.")

    # Return the first page target (the kiosk tab).
    return pages[0]["webSocketDebuggerUrl"]


def navigate(target_url: str) -> None:
    """Navigate the active browser tab to *target_url* via CDP."""
    ws_url = get_page_ws_url()
    ws = websocket.create_connection(ws_url, timeout=10)
    try:
        command = json.dumps(
            {"id": 1, "method": "Page.navigate", "params": {"url": target_url}}
        )
        ws.send(command)
        # Wait for acknowledgement.
        result = json.loads(ws.recv())
        if "error" in result:
            raise RuntimeError(f"CDP navigation error: {result['error']}")
    finally:
        ws.close()


def main() -> None:
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} navigate <url>", file=sys.stderr)
        sys.exit(1)

    action = sys.argv[1]
    if action != "navigate":
        print(f"Unknown action: {action}", file=sys.stderr)
        sys.exit(1)

    target_url = sys.argv[2]
    try:
        navigate(target_url)
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
