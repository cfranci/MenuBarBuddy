import AppKit
import SwiftUI
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    // Created FIRST = rightmost = always visible (just like Hidden Bar's btnExpandCollapse)
    private let toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // Created SECOND = to the left of toggle = this expands (just like Hidden Bar's btnSeparate)
    private let separatorItem = NSStatusBar.system.statusItem(withLength: 1)

    private var settingsWindow: NSWindow?
    private var contextMenu: NSMenu!
    private var hotKey: HotKey?

    private let settingsStore = SettingsStore.shared
    private var collapseLength: CGFloat = 2000
    private let expandedLength: CGFloat = 20

    private var isCollapsed: Bool {
        return separatorItem.length > expandedLength
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateCollapseLength()
        setupUI()
        setupContextMenu()
        setupHotKey()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func updateCollapseLength() {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1728
        collapseLength = max(500, screenWidth * 2.5 * CGFloat(settingsStore.pushMultiplier))
    }

    @objc private func screenChanged() {
        updateCollapseLength()
    }

    private func setupHotKey() {
        hotKey = HotKey(key: .space, modifiers: [.control, .option])
        hotKey?.keyDownHandler = { [weak self] in
            self?.toggleMenuBar()
        }
    }

    private func setupUI() {
        // Toggle (📁) — rightmost, always visible, variable width
        if let button = toggleItem.button {
            button.title = settingsStore.selectedEmoji
            button.target = self
            button.action = #selector(toggleItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        toggleItem.autosaveName = "mbb3-toggle"

        // Separator (☰) — to the left of toggle, expands to hide items to its left
        if let button = separatorItem.button {
            button.title = settingsStore.startEmoji
        }
        separatorItem.autosaveName = "mbb3-separator"

        // Start expanded (separator at normal width)
        separatorItem.length = expandedLength
    }

    private func setupContextMenu() {
        contextMenu = NSMenu()
        updateContextMenuTitle()

        contextMenu.addItem(NSMenuItem.separator())

        let settingsMenuItem = NSMenuItem(title: "Choose Icons...", action: #selector(openSettings), keyEquivalent: "")
        settingsMenuItem.target = self
        contextMenu.addItem(settingsMenuItem)

        let hotkeyLabel = NSMenuItem(title: "Hotkey: Ctrl+Opt+Space", action: nil, keyEquivalent: "")
        hotkeyLabel.isEnabled = false
        contextMenu.addItem(hotkeyLabel)

        contextMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit MenuBarBuddy", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)
    }

    private func updateContextMenuTitle() {
        let title = isCollapsed ? "Expand Menu Bar" : "Collapse Menu Bar"
        if contextMenu.items.isEmpty {
            let item = NSMenuItem(title: title, action: #selector(toggleMenuBarAction), keyEquivalent: "")
            item.target = self
            contextMenu.insertItem(item, at: 0)
        } else {
            contextMenu.items[0].title = title
        }
    }

    @objc private func toggleItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            updateContextMenuTitle()
            toggleItem.menu = contextMenu
            toggleItem.button?.performClick(nil)
            toggleItem.menu = nil
        } else {
            toggleMenuBar()
        }
    }

    @objc private func toggleMenuBarAction() {
        toggleMenuBar()
    }

    private func toggleMenuBar() {
        if isCollapsed {
            expandMenuBar()
        } else {
            collapseMenuBar()
        }
    }

    private func collapseMenuBar() {
        // Validate separator is to the left of toggle (same check as Hidden Bar)
        guard let toggleX = toggleItem.button?.window?.frame.origin.x,
              let separatorX = separatorItem.button?.window?.frame.origin.x,
              toggleX >= separatorX else { return }

        separatorItem.button?.title = ""
        separatorItem.length = collapseLength
    }

    private func expandMenuBar() {
        separatorItem.length = expandedLength
        separatorItem.button?.title = settingsStore.startEmoji
    }

    // MARK: - Settings

    @objc private func openSettings() {
        if let existingWindow = settingsWindow {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            store: settingsStore,
            onEmojiChange: { [weak self] emoji in
                self?.toggleItem.button?.title = emoji
            },
            onStartEmojiChange: { [weak self] emoji in
                guard let self = self else { return }
                if !self.isCollapsed {
                    self.separatorItem.button?.title = emoji
                }
            },
            onPushMultiplierChange: { [weak self] in
                self?.updateCollapseLength()
            }
        )
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 350, height: 540)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MenuBarBuddy Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        self.settingsWindow = window

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            NSApp.setActivationPolicy(.accessory)
            self?.settingsWindow = nil
        }
    }

    @objc private func quitApp() {
        if isCollapsed {
            expandMenuBar()
        }
        NSApp.terminate(nil)
    }
}
