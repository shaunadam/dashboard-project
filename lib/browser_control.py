#!/usr/bin/env python3
"""Browser control via Chrome DevTools Protocol (CDP).

Controls Chromium using the remote debugging port.
Requires Chromium to be launched with --remote-debugging-port=9222.

Usage:
    python3 lib/browser_control.py navigate <url>
    python3 lib/browser_control.py inject-idle-tracker
    python3 lib/browser_control.py get-idle-ms

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

# JavaScript that installs touch/mouse/keyboard listeners to track last activity.
# Uses a global so get-idle-ms can read it back.
IDLE_TRACKER_JS = """
(function() {
    window.__lastActivity = Date.now();
    var events = ['touchstart', 'touchmove', 'mousedown', 'mousemove', 'keydown', 'scroll'];
    function onActivity() { window.__lastActivity = Date.now(); }
    events.forEach(function(evt) {
        document.addEventListener(evt, onActivity, {capture: true, passive: true});
    });
})();
""".strip()

# JavaScript that returns milliseconds since last user interaction.
# If the tracker hasn't been injected yet, returns -1 as a sentinel.
GET_IDLE_JS = """
(typeof window.__lastActivity === 'number')
    ? (Date.now() - window.__lastActivity)
    : -1
""".strip()


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


def _cdp_send(method: str, params: dict | None = None) -> dict:
    """Send a single CDP command and return the result."""
    ws_url = get_page_ws_url()
    ws = websocket.create_connection(
        ws_url, timeout=10, origin=f"http://{CDP_HOST}:{CDP_PORT}"
    )
    try:
        command = {"id": 1, "method": method}
        if params:
            command["params"] = params
        ws.send(json.dumps(command))
        result = json.loads(ws.recv())
        if "error" in result:
            raise RuntimeError(f"CDP error: {result['error']}")
        return result
    finally:
        ws.close()


def navigate(target_url: str) -> None:
    """Navigate the active browser tab to *target_url* via CDP."""
    _cdp_send("Page.navigate", {"url": target_url})


def inject_idle_tracker() -> None:
    """Install idle-tracking event listeners in the browser.

    Uses Page.addScriptToEvaluateOnNewDocument so the tracker persists
    across page navigations, plus Runtime.evaluate to install on the
    current page immediately.
    """
    # Persist across future navigations.
    _cdp_send(
        "Page.addScriptToEvaluateOnNewDocument", {"source": IDLE_TRACKER_JS}
    )
    # Install on current page now.
    _cdp_send("Runtime.evaluate", {"expression": IDLE_TRACKER_JS})


def get_idle_ms() -> int:
    """Return milliseconds since last user interaction, or -1 if tracker not injected."""
    result = _cdp_send("Runtime.evaluate", {"expression": GET_IDLE_JS})
    value = result.get("result", {}).get("result", {}).get("value")
    if value is None:
        return -1
    return int(value)


def main() -> None:
    if len(sys.argv) < 2:
        print(
            f"Usage: {sys.argv[0]} <navigate URL | inject-idle-tracker | get-idle-ms>",
            file=sys.stderr,
        )
        sys.exit(1)

    action = sys.argv[1]
    try:
        if action == "navigate":
            if len(sys.argv) < 3:
                print(f"Usage: {sys.argv[0]} navigate <url>", file=sys.stderr)
                sys.exit(1)
            navigate(sys.argv[2])
        elif action == "inject-idle-tracker":
            inject_idle_tracker()
        elif action == "get-idle-ms":
            idle = get_idle_ms()
            print(idle)
        else:
            print(f"Unknown action: {action}", file=sys.stderr)
            sys.exit(1)
    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
