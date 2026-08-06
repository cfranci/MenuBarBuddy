# Handoff — MenuBarBuddy
*Updated: 2026-07-11*

## Status: WORKING + HARDENED on macOS 26.2 (Tahoe)

The March collapse bug is fixed and verified end-to-end on the installed app
(hotkey toggle, screenshot-verified hide/restore across displays). A hardening
pass followed; current bundle ID is **com.menubarbuddy.v10**.

## July 11 2026: daily false alarm fixed + Appearance system

**The daily "icons are being blocked" alert was a watchdog false positive,
not real blacklisting.** The bundle ID climbed v6 → v10 in one week from
Ga'noh clicking "Repair and Relaunch" on bogus alerts. Root cause: the orphan
signature used single-display geometry. `window.frame.origin.y < 0` is a
legitimate coordinate when a display is arranged below/left of the main one
(this Mac runs 3+ displays incl. TouchProxy virtuals and a TV), and
display sleep / screen lock / display reconfiguration all detach or move the
status item windows for longer than the 15s streak. Fixes in `checkHosting`/
`itemsLookOrphaned`:

- Watchdog stands down while screens are asleep or the session is locked
  (NSWorkspace + com.apple.screenIsLocked distributed notifications), for
  60s after any display reconfiguration or wake, 30s after unlock, and while
  any mouse button is down.
- "Parked" now means the window intersects NO online screen (was `y < 0`).
- Recovery attempts reset after 24h without incident (isolated transients
  no longer accumulate into the alert); the alert itself is throttled to
  once per 20h persisted across relaunches (`MenuBarBuddy.lastRepairAlertAt`).
- Every orphan verdict now NSLogs which sub-check tripped.
- `applicationShouldTerminate` expands before ANY termination path
  (AppleScript quit, logout) — previously only quitApp()/signals expanded,
  and install.sh's `tell app to quit` could kill a collapsed instance.
- install.sh now quits the app BEFORE touching the bundle and keeps the
  HIGHER bundle-ID vN between Support/Info.plist and the installed app, so a
  reinstall can never revert to a blacklisted ID (Support/Info.plist synced
  to v10).

**Appearance system** (replaces the single "Rainbow Dot" toggle; right-click
→ Appearance):

- **Style**: Classic Green, Rainbow, Ocean, Lava, Aurora, Custom Color…
  (NSColorPanel; hue persisted as `MenuBarBuddy.customDotHue`).
- **Motion**: Wave (default), Ripple (radial rings), Spin (rotating conic),
  Breathe (radius pulse), Steady (fixed split). **Motions LAYER**: the menu
  items toggle a set, any combination runs at once (each active motion
  contributes a per-pixel blend component and they're averaged; breathe
  modulates the radius independently). Empty set = solid top color.
- **Speed**: Slow / Normal / Fast (0.5x / 1x / 2x).
- Persisted as `MenuBarBuddy.dotStyle/dotMotion/dotSpeed`; dotMotion is a
  comma-joined list ("breathe,spin,wave"), and a bare single value from
  older builds parses fine. All in the SettingsStore migration list.
  Back-compat: old `rainbowDot=true` maps to Rainbow; the flag is kept
  coherent for downgrades.
- Renderer: `makeStyledDotImage` (generalized `makeWaveDotImage`), same
  36x36 bitmap at 20fps, same vividness rule (gray when collapsed + idle).
- Verified live: install, hotkey collapse/expand cycle, dot renders and
  grays correctly (screenshots).

**Site demo** (`site/index.html`): the hero demo now has Style + Motion chip
rows mirroring the app (Classic/Rainbow/Ocean/Lava/Aurora x
Wave/Ripple/Spin/Breathe/Steady). Motion chips are multi-select like the
app: JS composes the active animations inline on `.dot` (wave animates
background-position, ripple background-size, spin transform-rotate), breathe
scales a `.dot-wrap` wrapper so it never fights spin on `transform`, and the
collapsed pause rules use `!important` because inline animation shorthand
would otherwise reset play-state. Verified with Playwright (layered combos,
pause-when-collapsed, empty-set static state; no page errors). NOTE: GitHub Pages is NOT enabled yet and {BUY_URL} is
still a placeholder — the site is pre-launch. A Supabase "live demo" backend
was considered and rejected: the demo is client-side and needs no data,
accounts, or state; a backend adds cost and an outage surface for zero
visitor-visible gain.

## Menu bar arrangement (as of close, July 3 2026)

- **Hidden zone** (left of │, hides on collapse): dictation mic pill (system,
  transient), Docker whale (with ! badge), waveform icon, dot-grid icon,
  Wi-Fi, keyboard/input switcher.
- **Always visible** (right of the dot): weather (cloud + °F), play button,
  battery %, screen-mirroring pill (purple when active), Control Center
  toggles, clock. The dot sits immediately right of │ (separator 380pt /
  toggle 346pt from the right edge; the between-zone is currently empty).

## Rainbow Dot (optional mode, currently ON)

Right-click the dot → "Rainbow Dot" to toggle (persisted as
`MenuBarBuddy.rainbowDot`, migrates across bundle IDs). The dot is TWO-TONE:
one hue on top, a second hue (a third of the wheel away) below, blended along
a wavy boundary that drifts through the middle (~one sweep every 4s, rendered
per-pixel in `makeWaveDotImage`, 36x36 retina bitmap at 20fps). Both hues
phase through a full cycle every ~8s. Vividness follows the classic rule:
saturated and bright when expanded or hovered (sat 0.90 / bright 1.0), grayed
out when collapsed and idle (sat 0.15 / bright 0.55), eased over ~0.8s.
Classic green/gray mode is the default when the option is off.

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
  Works in BOTH states: the toggle is checked even while collapsed (an early
  version skipped collapsed state and went blind — fixed). Three consecutive
  positives → recreate the status items in-process (twice max) → then a
  one-time alert offering **Repair and Relaunch**. LIVE-FIRE TESTED: a debug
  harness accidentally died while collapsed, blacklisting v5; the watchdog
  detected it, ran both recreations, and raised the alert on its own.
- **Self-repair** (`performSelfRepair`, also `--force-repair` flag): bumps its
  own CFBundleIdentifier (v5 → v6 → ...), re-signs ad hoc, relaunches; the
  settings/position migration follows the domain chain automatically
  (`SettingsStore.previousBundleIDs` is derived from the current ID). Tested
  live twice: v4 → v5 and v5 → v6 both worked end to end. **After a
  self-repair, sync `Support/Info.plist` to the new ID** or install.sh will
  revert it.
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
- Never kill/restart the app while a menu bar item is being dragged, and
  never terminate while collapsed (debug harnesses exit via quitApp(), which
  expands first — killing mid-push is how v5 died).
- The dictation/screen-recording pills are system indicators; they sit in the
  pushed zone and hide/restore with the rest. Normal.
- macOS 26 spacing knobs if the bar gets crowded:
  `defaults -currentHost write -globalDomain NSStatusItemSpacing -int 12` (and
  `NSStatusItemSelectionPadding`).
