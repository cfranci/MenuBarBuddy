# MenuBarBuddy

A lightweight macOS menu bar manager that lets you hide and show menu bar icons with a single click.

## How It Works

MenuBarBuddy adds two items to your menu bar:

- **The dot** (right) — a small colored dot. Click to collapse/expand. Always visible: green (or animated rainbow) when expanded, grayed out when collapsed and idle, vivid on hover.
- **│ Separator** (left of the dot) — a thin line marking the boundary. Everything to its left gets hidden when collapsed.

### Positioning

By default, all your other menu bar items sit to the left of │ and will be hidden when you collapse.

To keep certain items **always visible**, Cmd-drag them to be **between** │ and the dot.

### Controls

- **Left-click** the dot to toggle collapse/expand
- **Right-click** the dot for the context menu (settings, quit)
- **Ctrl+Opt+Space** hotkey to toggle from anywhere
- **Cmd-drag** │ to reposition the boundary

## Customization

Right-click the dot → **Rainbow Dot** to make it phase through the color
wheel (~8s per cycle): grayed out while collapsed and idle, vivid on hover or
when expanded. Right-click → **Start at Login** to keep it running after
reboots.

Right-click the dot → **Choose Icons...** opens the icon picker window.
Note: the custom emoji pickers in this window are currently non-functional
(the toggle always renders as the dot); see docs/pre-launch-review.md. The
working customizations are Rainbow Dot and Start at Login.

## Requirements

- macOS 14+ (verified on macOS 26 Tahoe)

## Building

```bash
./install.sh
```

Builds a release binary, assembles `/Applications/MenuBarBuddy.app` from
`Support/Info.plist`, codesigns, and relaunches.

> macOS 26 note: `NSStatusItem.length` is hard-capped at 10,000 and throws
> above it. See HANDOFF.md for the full Tahoe compatibility story.

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) — Global keyboard shortcut support
