#!/bin/zsh
# Build MenuBarBuddy and (re)install it to /Applications.
set -e
cd "$(dirname "$0")"

swift build -c release

APP=/Applications/MenuBarBuddy.app

# Never revert the bundle ID: self-repairs bump it (v6 -> v7 -> ...) to escape
# macOS 26's blacklist, and reinstalling an older (blacklisted) ID orphans the
# icons instantly. Keep whichever of Support/Info.plist vs the installed app
# carries the higher vN.
SRC_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' Support/Info.plist)
KEEP_ID=$SRC_ID
if [[ -f "$APP/Contents/Info.plist" ]]; then
  CUR_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist" 2>/dev/null || echo "")
  SRC_N=${SRC_ID##*.v}
  CUR_N=${CUR_ID##*.v}
  if [[ "$SRC_N" == <-> && "$CUR_N" == <-> && $CUR_N -gt $SRC_N ]]; then
    KEEP_ID=$CUR_ID
  fi
fi

# Quit gracefully BEFORE touching the bundle: a violent kill while the menu
# bar host is touching a status item gets the bundle ID blacklisted on
# macOS 26 (see HANDOFF.md).
osascript -e 'tell application "MenuBarBuddy" to quit' 2>/dev/null || true
sleep 1
pkill -x MenuBarBuddy 2>/dev/null || true
sleep 1

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Support/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $KEEP_ID" "$APP/Contents/Info.plist"
cp .build/release/MenuBarBuddy "$APP/Contents/MacOS/MenuBarBuddy"
codesign --force -s - "$APP"

echo "Installed as $KEEP_ID. Relaunching..."
open "$APP"
