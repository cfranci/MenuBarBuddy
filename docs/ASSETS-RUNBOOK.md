# Asset Capture Runbook (Armada stitched output, 2026-07-08)

> Executed 2026-07-08. Final assets in site/assets/: before.png, after.png, menu.png, demo.mp4 (65KB), poster.png, og.png, demo.gif (bonus). Captured from the live app on the Tahoe Mac, including a live self-repair (v7 to v8) mid-session.

# MenuBarBuddy Assets Capture Runbook (execute on this Mac)

## Verified facts (do NOT re-derive — checked live 2026-07-08)

- **Display**: physical 3456x2234 Retina, **logical 2056x1329 points, 2x scale** (confirmed via `Finder desktop bounds` = `0,0,2056,1329`). Use **2056** as the point width for every `-R` and crop offset. (Haiku's 1728/3456 numbers are WRONG — do not use them.)
- **Menu bar strip**: `screencapture -x -R 0,0,2056,40` yields a **4112x80 retina PNG** (confirmed live).
- **Notch**: physical x ≈ 1896-2216 (logical ≈ 948-1108). Any crop that starts right of physical x=2400 is notch-safe.
- **The shipped icon is a colored DOT, not a folder.** The README's "📁 Folder" language is legacy. Right marker = a colored dot (green idle, or two-tone Rainbow when enabled); left marker = a thin `│` separator glyph. All captures must show the dot.
- **Dot / separator position** (from HANDOFF.md, authoritative): toggle (dot) sits **346pt from the right edge**, separator **380pt from the right edge**. Logical x of the dot = **2056 − 346 = 1710pt**, y ≈ 10pt (menu-bar middle). Use **1710,10**, NOT opus's 1826.
- **Rainbow Dot is currently ON** (HANDOFF: "optional mode, currently ON"). The dot already cycles a two-tone wave: vivid (sat 0.90/bright 1.0) when expanded or hovered, grayed (sat 0.15/bright 0.55) when collapsed+idle, eased ~0.8s. Do NOT script a "turn Rainbow on" video beat — it starts on; toggling would turn it OFF.
- **Exact right-click context-menu order** (read from AppDelegate.swift `setupContextMenu`, top→bottom): (1) **Expand/Collapse Menu Bar** [dynamic], (2) separator, (3) **Choose Icons...**, (4) **Hotkey: Ctrl+Opt+Space** [disabled label], (5) **Start at Login**, (6) **Rainbow Dot**, (7) separator, (8) **Quit MenuBarBuddy** [⌘Q]. macOS arrow-nav skips separators+disabled items, so from menu-open: **one Down lands on Expand/Collapse, a second Down lands on Choose Icons...**.
- **Hotkey toggle** (verified, exits 0): `osascript -e 'tell application "System Events" to key code 49 using {control down, option down}'`.
- **Tools present** (all at /opt/homebrew/bin): `ffmpeg` 8.1.1, `magick` (ImageMagick 7 — use `magick`, never `convert`), `cliclick` 5.1. avfoundation screen device is index `[3]` (Capture screen 0). `screencapture -v` also works zero-config.
- **App is RUNNING** (pgrep -x MenuBarBuddy → live). Never relaunch a second instance (single-instance guard).
- **Site**: `/Users/cf/Projects/MenuBarBuddy/site/index.html` EXISTS and references exactly these assets: **`assets/before.png`, `assets/after.png`, `assets/icons.png`, `assets/demo.mp4`, `assets/poster.png`, `assets/og.png`** (the social card — none of the source attempts caught og.png; produce it). before/after are shown side-by-side in a `.shots` grid (NOT a crossfade), and the demo `<video>` uses `poster="assets/poster.png"`.
- **Scratch**: `/tmp/mbb-capture`. **Finals**: `/Users/cf/Projects/MenuBarBuddy/site/assets/` (verified empty, waiting).

## Safety contract (enforce at EVERY step)

- **Never `pkill`/`kill` the app mid-drag or while collapsed** — that blacklists the bundle ID (HANDOFF: v5 died this way; blacklist survives an isVisible bounce, needs `--force-repair` or a new bundle ID). Note: graceful `pkill`/Ctrl-C now runs an expand-and-quit path (HANDOFF confirms), but you have **no reason to kill it at all** — just leave it running.
- **Toggle only via the verified hotkey** (or a menu click). Never Cmd-drag the dot yourself.
- **End every step, and the whole session, with the app EXPANDED.** After any collapse, immediately re-expand and verify with a strip screenshot before moving on.
- **Reveal / restore the menu bar**: it is hidden on the fullscreen iTerm2 space. Activate Finder before every capture; restore iTerm2 focus afterward so the workspace is left as found.

**Emergency restore (run any time you're unsure of state):**
```bash
osascript -e 'tell application "System Events" to key code 49 using {control down, option down}'
sleep 1
osascript -e 'tell application "Finder" to activate'; sleep 0.4
screencapture -x -R 0,0,2056,40 /tmp/mbb-capture/verify-expanded.png
# Eyeball: dot + icons left of │ visible = expanded. If the dot is missing entirely,
# run: /Applications/MenuBarBuddy.app/Contents/MacOS/MenuBarBuddy --force-repair
```

---

## 0. Setup (run once)

```bash
mkdir -p /tmp/mbb-capture /Users/cf/Projects/MenuBarBuddy/site/assets
pgrep -x MenuBarBuddy >/dev/null && echo "MBB running (do NOT relaunch)" || open /Applications/MenuBarBuddy.app
which ffmpeg magick cliclick
# Reveal the bar, confirm expanded, confirm the dot's icon cluster is visible
osascript -e 'tell application "Finder" to activate'; sleep 0.5
screencapture -x -R 0,0,2056,40 /tmp/mbb-capture/s0-sanity.png
# open /tmp/mbb-capture/s0-sanity.png  # visually confirm: dot on the right, │ + icons to its left
```

If `s0-sanity.png` looks collapsed (nothing left of `│`), toggle once to expand and re-shoot before proceeding. **Note on "before" clutter:** the hidden zone holds mostly *transient* system indicators (dictation mic pill, plus whatever apps are running). If the strip looks thin, that is real system state, not a bug — open Docker/other menu-bar apps first if you want a fuller "before," or just accept the honest current state.

---

## 1. Screenshot A — "Before" (expanded / cluttered)

```bash
osascript -e 'tell application "Finder" to activate'; sleep 0.5
# App starts expanded; capture the full strip.
screencapture -x -R 0,0,2056,40 /tmp/mbb-capture/before-raw.png
sips -g pixelWidth -g pixelHeight /tmp/mbb-capture/before-raw.png   # expect 4112 x 80
# App stays EXPANDED (no toggle happened).
```

---

## 2. Screenshot B — "After" (collapsed / clean)

Uses the IDENTICAL crop as "before" so both grid tiles line up on the right-side landmarks.

```bash
osascript -e 'tell application "Finder" to activate'; sleep 0.3
osascript -e 'tell application "System Events" to key code 49 using {control down, option down}'  # collapse
sleep 2.0   # HANDOFF: collapse self-verifies at 1.5s; wait past that
screencapture -x -R 0,0,2056,40 /tmp/mbb-capture/after-raw.png
sips -g pixelWidth -g pixelHeight /tmp/mbb-capture/after-raw.png
# CRITICAL: re-expand immediately so we never leave the app collapsed
osascript -e 'tell application "System Events" to key code 49 using {control down, option down}'  # expand
sleep 1.5
screencapture -x -R 0,0,2056,40 /tmp/mbb-capture/b-expanded-verify.png   # confirm expanded
```

### Crop + frame before/after (identical region, ImageMagick 7)

The interesting right-side region (notch-free) is the last ~1400 retina px. Crop both identically, then apply a simple rounded-corner + shadow frame (the clear `roundrectangle`+`shadow` recipe from sonnet-a/b, NOT opus's cryptic polygon).

```bash
cd /tmp/mbb-capture
for f in before after; do
  # Identical crop: right 1400px of the 4112-wide strip, full 80px height (notch-safe: starts at x=2712)
  magick ${f}-raw.png -crop 1400x80+2712+0 +repage ${f}-crop.png
  # Rounded corners (r=16) + drop shadow, on a transparent canvas
  W=$(magick identify -format "%w" ${f}-crop.png); H=$(magick identify -format "%h" ${f}-crop.png)
  magick ${f}-crop.png \
    \( +clone -alpha extract -fill black -background black \
       -draw "fill white roundrectangle 0,0 $((W-1)),$((H-1)) 16,16" -alpha off \) \
    -compose CopyOpacity -composite \
    \( +clone -background black -shadow 50x10+0+6 \) +swap -background none -layers merge +repage \
    ${f}.png
done
cp before.png /Users/cf/Projects/MenuBarBuddy/site/assets/before.png
cp after.png  /Users/cf/Projects/MenuBarBuddy/site/assets/after.png
```

---

## 3. Screenshot C — Choose Icons panel

The "Choose Icons..." item opens the SwiftUI `SettingsView` (350x540, centered, activation policy flips to `.regular` so it's capturable by window id). Drive the menu deterministically with cliclick + the *verified* menu order (Down, Down, Return reaches Choose Icons...).

```bash
osascript -e 'tell application "Finder" to activate'; sleep 0.4
cliclick rc:1710,10        # right-click the DOT (rc = right-click) -> context menu opens
sleep 0.5
# Verified order: Down=Expand/Collapse, Down=Choose Icons..., Return
osascript -e '
tell application "System Events"
  key code 125
  delay 0.1
  key code 125
  delay 0.1
  key code 36
end tell'
sleep 0.9                  # SettingsView opens + centers (window.center())
# Prefer a clean shadowed window PNG via window id; centered-rect fallback if lookup fails
WID=$(osascript -e 'tell application "System Events" to id of window 1 of (first process whose name is "MenuBarBuddy")' 2>/dev/null)
if [ -n "$WID" ]; then
  screencapture -x -o -l"$WID" /tmp/mbb-capture/icons-raw.png
else
  screencapture -x -R $(( (2056-350)/2 )),$(( (1329-540)/2 )),350,540 /tmp/mbb-capture/icons-raw.png
fi
# Close the panel with Cmd-W (reverts activation policy to .accessory via willClose observer) — NEVER Quit
osascript -e 'tell application "System Events" to keystroke "w" using command down'
sleep 0.3
# Light shadow, ship
magick /tmp/mbb-capture/icons-raw.png \
  \( +clone -background black -shadow 60x12+0+6 \) +swap -background none -layers merge +repage \
  /Users/cf/Projects/MenuBarBuddy/site/assets/icons.png
```

**Fallback if automation drifts** (e.g. dot was Cmd-dragged so 1710,10 misses): `echo "Right-click the dot, click Choose Icons... (5s)"; sleep 5; screencapture -x /tmp/mbb-capture/icons-fullscreen.png` then crop the centered 350x540 window. Confirm the panel shows the quick-pick emoji/symbol grid (not the system Character Viewer — that's a different, wrong window).

**Verify expanded** after: `screencapture -x -R 0,0,2056,40 /tmp/mbb-capture/c-verify.png`.

---

## 4. Screenshot D — right-click context menu (bonus, for README/PH; not referenced by index.html)

```bash
osascript -e 'tell application "Finder" to activate'; sleep 0.4
cliclick rc:1710,10        # open the menu at the dot
sleep 0.5
# Menu drops below the dot on the right; capture a region covering dot + menu
screencapture -x -R 1560,0,400,300 /tmp/mbb-capture/menu-raw.png
cliclick kp:esc            # dismiss WITHOUT selecting (never land on Quit)
sleep 0.2
# If clipped, widen: screencapture -x -R 1520,0,440,320 ...  then re-shoot
magick /tmp/mbb-capture/menu-raw.png \
  \( +clone -background black -shadow 40x10+0+5 \) +swap -background none -layers merge +repage \
  /Users/cf/Projects/MenuBarBuddy/site/assets/context-menu.png   # optional, index.html does not use it
```

---

## 5. Demo video (15-22s)

**Storyboard** — Rainbow Dot is ALREADY ON, so lean on it. Do not toggle it. Beats driven by a foreground script while a background recorder runs.

- **0-2s** — Cluttered expanded bar, dot cycling a vivid two-tone rainbow. Establish the mess.
- **2-3s** — Cursor moves to the dot (stays vivid on hover).
- **3-5s** — Collapse (left-click the dot / hotkey). Icons slide left, vanish behind `│`.
- **5-8s** — Beat on the clean bar; cursor rests. Dot grays to idle (collapsed+idle = gray, per updateDotColor).
- **8-10s** — Ctrl+Opt+Space hotkey → expand. Icons reappear (shows the global hotkey).
- **10-14s** — Right-click the dot → context menu appears (shows Choose Icons, Rainbow Dot, Start at Login, Quit). Esc to dismiss.
- **14-20s** — Cursor rests on the dot; end on a vivid rainbow frame. Fade. **App left EXPANDED.**

### Record + drive beats (one backgrounded recorder, one foreground beat script)

Use `screencapture -v` (zero-config, verified) recording a strip 200pt tall so the dropped menu is captured too.

```bash
osascript -e 'tell application "Finder" to activate'; sleep 0.4
# Background recorder, 25s cap, strip region tall enough for the menu (200pt -> 400px retina)
screencapture -x -v -V 25 -R 0,0,2056,200 /tmp/mbb-capture/raw-capture.mov &
RECPID=$!
# --- foreground beats (run inline, same session) ---
sleep 2   # 0-2s establish
cliclick m:1710,10;  sleep 1                                                                 # 2-3s hover
cliclick c:1710,10;  sleep 2.5                                                               # 3-5.5s collapse (left-click)
osascript -e 'tell application "System Events" to key code 49 using {control down, option down}'; sleep 2.5  # expand @~8s
cliclick rc:1710,10; sleep 3                                                                 # menu @~10-13s
cliclick kp:esc;     sleep 0.3
cliclick m:1710,10;  sleep 5                                                                 # hover, rainbow finish
wait $RECPID 2>/dev/null || true
# Safety: guarantee expanded (collapse was via left-click; if the timeline drifted, this normalizes)
screencapture -x -R 0,0,2056,40 /tmp/mbb-capture/post-record.png
osascript -e 'tell application "iTerm2" to activate' 2>/dev/null || osascript -e 'tell application "iTerm" to activate'
```

> If a left-click on the dot does NOT collapse in your build (the toggle only responds to certain events), swap the collapse beat for the hotkey: `osascript -e 'tell application "System Events" to key code 49 using {control down, option down}'`.

### Encode to H.264 <3MB (with escalation ladder)

Crop to the strip, keep the top ~120pt (240px retina, room for a dropped menu), scale for web. Height must stay tall enough to be visible in a player (never ship a 40px-tall video).

```bash
cd /tmp/mbb-capture
ffmpeg -y -i raw-capture.mov \
  -vf "crop=4112:240:0:0, scale=1600:-2:flags=lanczos, format=yuv420p" \
  -c:v libx264 -preset slow -crf 26 -movflags +faststart -an \
  demo.mp4
ls -lh demo.mp4   # confirm < 3MB
# Escalation if over 3MB, in order: raise -crf (26 -> 30 -> 34), then drop scale (1600 -> 1200 -> 1000), then trim (-t 18)
cp demo.mp4 /Users/cf/Projects/MenuBarBuddy/site/assets/demo.mp4
```

### Poster frame (rainbow finish — the strong marketing frame, per opus)

```bash
cd /tmp/mbb-capture
ffmpeg -y -ss 19 -i demo.mp4 -frames:v 1 poster.png   # ~19s = vivid rainbow end beat
cp poster.png /Users/cf/Projects/MenuBarBuddy/site/assets/poster.png
```

### Optional GIF (two-pass palette from the .mov, 11fps — for README/Product Hunt)

Generate the palette from the FILE (not live avfoundation), so nothing hangs.

```bash
cd /tmp/mbb-capture
ffmpeg -y -i raw-capture.mov -vf "crop=4112:240:0:0,fps=11,scale=1000:-1:flags=lanczos,palettegen=stats_mode=diff" palette.png
ffmpeg -y -i raw-capture.mov -i palette.png \
  -filter_complex "crop=4112:240:0:0,fps=11,scale=1000:-1:flags=lanczos[v];[v][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
  demo.gif
ls -lh demo.gif   # if > 1.5MB: fps=10, scale=800, or -ss/-t trim to ~8s
cp demo.gif /Users/cf/Projects/MenuBarBuddy/site/assets/demo.gif   # optional; index.html does not reference it
```

---

## 6. og.png — social share card (referenced by index.html `og:image` + `twitter:image`; no attempt produced it)

1200x630 is the OG standard. Compose the collapsed "after" strip over a branded background so link previews look intentional.

```bash
cd /tmp/mbb-capture
# Dark card with the clean/collapsed strip centered and a wordmark
magick -size 1200x630 "xc:#0b0d0e" \
  \( after-crop.png -resize 1000x \) -gravity center -geometry +0-40 -composite \
  -gravity center -font Helvetica-Bold -pointsize 52 -fill white -annotate +0+140 "MenuBarBuddy" \
  -gravity center -font Helvetica -pointsize 26 -fill "#9aa0a6" -annotate +0+200 "One click. Cluttered to calm." \
  /Users/cf/Projects/MenuBarBuddy/site/assets/og.png
# (Adjust font names if Helvetica-Bold is unavailable: magick -list font | grep -i helvetica)
```

---

## 7. Final verification + teardown (run last, every time)

```bash
osascript -e 'tell application "Finder" to activate'; sleep 0.3
screencapture -x -R 0,0,2056,40 /tmp/mbb-capture/final-verify.png   # eyeball: expanded, dot + left cluster visible
pgrep -x MenuBarBuddy && echo "app alive" || echo "WARN: app not running"
# Rainbow Dot should still be ON (never toggled it) — nothing to restore
osascript -e 'tell application "iTerm2" to activate' 2>/dev/null || osascript -e 'tell application "iTerm" to activate'
ls -lh /Users/cf/Projects/MenuBarBuddy/site/assets/
#   REQUIRED by index.html: before.png after.png icons.png demo.mp4 poster.png og.png
#   Optional extras:         context-menu.png demo.gif
```

If `final-verify.png` shows a collapsed bar, toggle once to expand and re-verify. Do NOT leave this Mac with the menu bar collapsed. **Keep `/tmp/mbb-capture` until every file in `site/assets` is confirmed** — do NOT `rm -rf` the scratch dir before that (Haiku's teardown destroyed sources prematurely).

### Confirm the assets actually render (real verification, missed by all attempts)

```bash
python3 -m http.server --bind 127.0.0.1 8099 --directory /Users/cf/Projects/MenuBarBuddy/site >/dev/null 2>&1 &
SRV=$!; sleep 1
open -a "Google Chrome" "http://127.0.0.1:8099/"
# Eyeball: before/after tiles, the Choose Icons image, and the demo video poster all load (no broken-image placeholders).
# When done: kill $SRV
```

---

## Gotchas specific to this capture

- **Dot at 1710,10** assumes the seeded position (346pt from right). If someone Cmd-dragged it, `cliclick`/click coords miss — re-derive by shooting a strip and measuring, or use the manual-assist fallback. `normalizeSavedPositions()` forces a stray dot back to 20pt from the right edge at launch, so a fresh launch is predictable.
- **`cliclick rc:` opens the menu; `c:` (left-click) toggles collapse.** Don't mix them up. Dismiss menus with `cliclick kp:esc`, never by clicking a row (avoids landing on Quit).
- **Choose Icons window** flips to `.regular` (shows in app switcher, capturable by window id) and reverts to `.accessory` on Cmd-W. Always close with Cmd-W, never Quit from it.
- **Menu arrow-nav**: Down×2 + Return reaches Choose Icons because macOS skips the separator and the disabled "Hotkey:" label. Verified against `setupContextMenu` order.
- **Transient "before" clutter**: dictation pill and app icons come and go — a thin "before" shot is honest system state, not a failure.
- **Video height**: always crop/scale to a visible height (≥120pt/240px shown here). A 40px-tall video is invisible in players — the bug in sonnet-a's `scale=2048:40`.

## Open questions
- Whether a left-click on the dot collapses in the installed build, or only the hotkey does — the video collapse beat assumes left-click works; a hotkey fallback is provided inline if not.
- The exact SettingsView title bar / window chrome for the Choose Icons capture — window-id capture handles it, but if the panel opens off-center on a fresh SwiftUI layout the centered-rect fallback offset may need a nudge.
- og.png font availability (Helvetica-Bold) — a `magick -list font` check may be needed on this machine to pick an installed face.