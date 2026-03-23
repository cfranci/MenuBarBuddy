# Handoff — MenuBarBuddy
*Generated: 2026-03-23*

## Last Working On
Debugging a collapse bug on macOS 26 (Tahoe). The app's core mechanism — setting a huge `NSStatusItem.length` on the separator to push other menu bar items off-screen — is broken. Clicking the dot clears the separator text but items don't get pushed, leaving the separator invisible and unclickable.

## Status
- **App architecture**: Working — Swift Package, two status items (dot toggle + separator), HotKey for global shortcut, SwiftUI settings window
- **Collapse mechanism**: BROKEN on macOS 26.2. The width-push trick that worked on macOS 14-15 no longer hides items. This is the same class of bug as the "status items breaking after reboot" fix (commit abe77d5)
- **Installed copy**: `/Applications/MenuBarBuddy.app/` (stale binary from before this debug session)

## Investigation Done
- Tried replacing the `isCollapsed` computed property (reads back `separatorItem.length`) with a stored `_collapsed` boolean — didn't fix it alone, confirming the issue is the collapse mechanism itself, not just state tracking
- Added debug prints but didn't get to read the output before closing
- macOS 26 likely clamps or ignores very large `NSStatusItem.length` values

## Next Steps
1. Add debug logging and run from terminal to confirm what `separatorItem.length` actually reports after being set
2. Research how other menu bar hider apps (Ice, Hidden Bar) handle macOS 26 — they use the same width trick
3. Possible alternative approaches: multiple filler status items, `NSStatusItem.isVisible`, or new macOS 26 APIs
4. The `autosaveName` keys cleared in `setupUI()` use "mbb3-toggle"/"mbb3-separator" but no `autosaveName` is set on the items — verify those UserDefaults keys are even doing anything

## Open Branches
- `main` only (up to date with origin)

## Key Commands
```bash
swift build
cp .build/debug/MenuBarBuddy MenuBarBuddy.app/Contents/MacOS/MenuBarBuddy
open MenuBarBuddy.app
```

## Resume Notes
- The app needs Accessibility permissions — when rebuilding, remind user to remove old entry from Privacy > Accessibility before replacing the binary
- The installed app is at `/Applications/MenuBarBuddy.app/`
- There was also a copy at `/Users/cf/Projects/MenuBarBuddy/` (capital P) with its own `.build` dir — that's likely the original dev directory
