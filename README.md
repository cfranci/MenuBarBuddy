# MenuBarBuddy

A lightweight macOS menu bar manager that lets you hide and show menu bar icons with a single click.

## How It Works

MenuBarBuddy adds two icons to your menu bar:

- **📁 Folder** (right) — Click to collapse/expand. Always visible.
- **☰ Separator** (left of folder) — Marks the boundary. Everything to its left gets hidden when collapsed.

### Positioning

By default, all your other menu bar items sit to the left of ☰ and will be hidden when you collapse.

To keep certain items **always visible**, Cmd-drag them to be **between** ☰ and 📁.

### Controls

- **Left-click** 📁 to toggle collapse/expand
- **Right-click** 📁 for the context menu (settings, quit)
- **Ctrl+Opt+Space** hotkey to toggle from anywhere
- **Cmd-drag** ☰ to reposition the boundary

## Customization

Right-click 📁 → **Choose Icons...** to:

- Change either icon to any emoji or symbol
- Use the system Character Viewer for the full emoji catalog
- Pick from a grid of quick-pick icons

## Requirements

- macOS 14+

## Building

```bash
swift build
cp .build/debug/MenuBarBuddy MenuBarBuddy.app/Contents/MacOS/MenuBarBuddy
open MenuBarBuddy.app
```

## Dependencies

- [HotKey](https://github.com/soffes/HotKey) — Global keyboard shortcut support
