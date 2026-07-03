# Handoff — MenuBarBuddy
*Updated: 2026-07-03 (late evening)*

## Status: WORKING + HARDENED on macOS 26.2 (Tahoe)

The March collapse bug is fixed and verified end-to-end on the installed app
(hotkey toggle, screenshot-verified hide/restore across displays). A hardening
pass followed; current bundle ID is **com.menubarbuddy.v5**.

## Hardening pass (all live-tested unless noted)

- **ObjC exception shield** (`Sources/ExceptionShield`, `MBBTryCatch`): every
  `NSStatusItem.length` write goes through `safelySetLength`, which catches the
  NSException AppKit throws above the system cap and falls back through
  5000/2500/1200. A future cap change degrades gracefully instead of silently
  killing clicks.
- **Collapse verification**: 1.5s after collapsing, if the separator window
  never grew, the app reverts to the expanded look so the UI never lies.
- **Hosting watchdog**: every ~5s the app checks for the orphaning signature
  (item windows parked at y<0, screenless, or overlapping at a display edge).
  Three consecutive positives → recreate the status items in-process (twice
  max) → then a one-time alert offering **Repair and Relaunch**.
- **Self-repair** (`performSelfRepair`, also `--force-repair` flag): bumps its
  own CFBundleIdentifier (v5 → v6 → ...), re-signs ad hoc, relaunches; the
  settings/position migration follows the domain chain automatically
  (`SettingsStore.previousBundleIDs` is derived from the current ID). Tested
  live: v4 → v5 worked end to end. **After a self-repair, sync
  `Support/Info.plist` to the new ID** or install.sh will revert it.
- **Proactive layout guard**: the mouse-poll timer checks every ~3s (when no
  mouse button is down) that the dot is right of the separator; two consecutive
  misorders → the dot pops back to the far right. No more self-hiding, even
  without a click.
- **Defaults sanitation**: non-finite/negative/absurd saved positions reset to
  seeds at launch.
- **Single-instance guard**: a second launch of the same bundle ID terminates
  itself (tested with `open -n`).
- **Graceful SIGTERM/SIGINT**: pkill/Ctrl-C now runs the expand-and-quit path
  instead of dying mid-manipulation (the blacklist trigger). Tested.
- **Start at Login** menu item (SMAppService), re-registered automatically
  after a bundle-ID bump via the `MenuBarBuddy.startAtLogin` flag. Not
  live-toggled in testing (needs a menu click), but compiles and re-asserts at
  launch.

## Root cause (three stacked problems)

1. **macOS 26 added a hard cap on `NSStatusItem.length`: 10,000.** Setting
   anything above it throws `NSInvalidArgumentException` ("maximum is 10000").
   The old formula `screenWidth * 2.5 * pushMultiplier` produced 10,800-16,000
   with the saved multiplier of 2. The exception is swallowed silently by the
   click/hotkey event handlers, so every toggle died mid-function: the
   separator glyph was already cleared (first statement) but the length was
   never set. Exactly the March symptom. Fix: `min(10_000, ...)` in
   `updateCollapseLength()`. (Ice works on Tahoe because its constant is
   exactly 10,000.)

2. **A crash while manipulating a status item makes Tahoe's Control Center
   orphan every status item registered under that bundle ID.** After one hard
   crash (uncaught length exception during a scripted test), all
   `com.menubarbuddy.app` items stopped being hosted: windows existed but were
   parked off-screen, invisible on every display. `killall ControlCenter` did
   NOT clear it. Escape: bundle ID is now **`com.menubarbuddy.v4`** (v2 → app → v3 → v4 so far; v3
   got blacklisted within hours when the process was killed mid-drag). Settings
   migrate automatically on first launch (`SettingsStore.migrateFromOldBundleID`).

3. **The items never had an `autosaveName`**, so positions persisted under
   generic `Item-0`/`Item-1` keys, and the launch-time "clear saved positions"
   code cleared `mbb3-*` keys that never existed (placebo since day one).
   Items now use real autosave names (`mbb3-toggle`, `mbb3-separator`), are
   forced `isVisible = true`, and seed their positions from the old bundle's
   layout (toggle 230pt / separator 388pt from the right edge). Without the
   seed, fresh items land far-left with nothing left of the separator to hide.

Also applied (Ice's Tahoe hygiene): while collapsed the separator is a pure
spacer — title cleared, `image = nil`, `cell?.isEnabled = false`,
`isHighlighted = false` — because Tahoe clamps the drawn extent of status
items that still have content.

## Layout guard (added after the dot self-hid)

The user can Cmd-drag the dot into the hidden zone (left of the separator);
clicking it there used to hide the dot itself with no visible way back. Now:

- `normalizeSavedPositions()` at launch: if saved positions put the toggle at
  or left of the separator, the toggle is forced to 20pt from the right edge.
- `layoutIsSafeToCollapse` before every collapse: compares both items' live
  distance-from-right-edge; if the dot is inside the hidden zone the collapse
  is refused and `healLayout()` re-inserts the dot on the safe side via a
  single `isVisible` bounce (defaults write + off/on + reconfigure button).
- No relaunch in the heal path, and install.sh quits the app via AppleScript
  before falling back to pkill: **killing the process while the menu bar host
  is mid-manipulation (e.g. during a drag) is what blacklists the bundle ID**
  — that's how v3 died within hours.
- An `isVisible` bounce does NOT cure an already-blacklisted bundle ID
  (tested; parked frames stay parked). Only an ID bump does.

## Build / install

```bash
./install.sh   # swift build -c release, assemble /Applications/MenuBarBuddy.app, codesign, relaunch
```

The app bundle recipe lives in `Support/Info.plist` (the bundle used to exist
only hand-made in /Applications).

## Debug harnesses (flag-gated, kept on purpose)

- `--test-collapse` — steps length 12→10,000, prints readback + window frames + CGWindowList
- `--test-visual` — collapse after 4s, expand after 12s, quit after 16s
- `--dump-state` — prints both items' isVisible/length/window frame once per second for 5s

Run the bundle binary directly (`/Applications/MenuBarBuddy.app/Contents/MacOS/MenuBarBuddy --dump-state`)
to get stdout while keeping bundle identity. Note: run UNBUNDLED
(`.build/release/MenuBarBuddy`) and you get a different defaults domain
("MenuBarBuddy"), which can hide/paper over bundle-domain bugs — that's what
made the March bug look timing-dependent.

## Gotchas for future work

- Never set `length` > 10,000 on macOS 26+ — it throws, and event handlers
  swallow the exception silently.
- If the items ever vanish from every display while the app runs fine, the
  app now detects it and offers Repair itself within ~1 minute. Manual
  fallback: run the app with `--force-repair`, then sync `Support/Info.plist`
  to the new bundle ID. Reboot may also clear the blacklist (untested).
- Never kill/restart the app while a menu bar item is being dragged.
- The dictation/screen-recording pills are system indicators; they sit in the
  pushed zone and hide/restore with the rest. Normal.
- macOS 26 spacing knobs if the bar gets crowded:
  `defaults -currentHost write -globalDomain NSStatusItemSpacing -int 12` (and
  `NSStatusItemSelectionPadding`).
