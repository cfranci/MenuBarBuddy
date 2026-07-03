#!/bin/zsh
# Build MenuBarBuddy and (re)install it to /Applications.
set -e
cd "$(dirname "$0")"

swift build -c release

APP=/Applications/MenuBarBuddy.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp .build/release/MenuBarBuddy "$APP/Contents/MacOS/MenuBarBuddy"
codesign --force -s - "$APP"

echo "Installed. Relaunching..."
# Quit gracefully first: a violent kill while the menu bar host is touching a
# status item gets the bundle ID blacklisted on macOS 26 (see HANDOFF.md).
osascript -e 'tell application "MenuBarBuddy" to quit' 2>/dev/null || true
sleep 1
pkill -x MenuBarBuddy 2>/dev/null || true
sleep 1
open "$APP"
