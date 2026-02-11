#!/bin/bash

# Set display environment variable
export DISPLAY=:0

# Wait for desktop to load
sleep 10

# Hide mouse cursor
unclutter -idle 0.1 &

# Start on-screen keyboard (auto-shows on text field focus)
GDK_BACKEND=x11 onboard --size=800x300 &

# Disable screen blanking
xset s off
xset -dpms
xset s noblank

# Start chromium in kiosk mode
chromium-browser \
  --kiosk \
  --disable-infobars \
  --disable-session-crashed-bubble \
  --disable-restore-session-state \
  --disable-web-security \
  --user-data-dir="$HOME/.config/chromium-kiosk" \
  --disable-features=TranslateUI \
  --no-first-run \
  --fast \
  --fast-start \
  --disable-default-apps \
  --password-store=basic \
  --display=:0 \
  http://192.168.68.75:8123
