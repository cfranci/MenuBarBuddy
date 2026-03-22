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
    private var mouseMonitor: Any?
    private var mouseTimer: Timer?
    private var colorAnimTimer: Timer?
    private var currentDotAlpha: CGFloat = 0.0  // 0 = gray, 1 = green
    private var targetDotAlpha: CGFloat = 0.0

    private let settingsStore = SettingsStore.shared
    private var collapseLength: CGFloat = 2000
    private let expandedLength: CGFloat = 12

    // Dot colors
    private let greenColor = NSColor(red: 120/255, green: 230/255, blue: 200/255, alpha: 1.0)
    private let grayColor = NSColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1.0)
    private var mouseInMenuBar = false

    private var isCollapsed: Bool {
        return separatorItem.length > expandedLength
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateCollapseLength()
        setupUI()
        setupContextMenu()
        setupHotKey()
        setupMouseTracking()

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

    // MARK: - Icon Drawing

    private func makeDotImage(color: NSColor, size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let dotSize: CGFloat = 9
        let origin = (size - dotSize) / 2
        let rect = NSRect(x: origin, y: origin, width: dotSize, height: dotSize)
        color.setFill()
        NSBezierPath(ovalIn: rect).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private func makeSeparatorImage(height: CGFloat = 18) -> NSImage {
        let width: CGFloat = 2
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        let barWidth: CGFloat = 1.5
        let barHeight: CGFloat = 12
        let x = (width - barWidth) / 2
        let y = (height - barHeight) / 2
        let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
        NSColor(white: 1.0, alpha: 0.35).setFill()
        NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    private func updateDotColor() {
        // Green if expanded (not collapsed) OR mouse is hovering over menu bar
        // Gray if collapsed and mouse is not in menu bar
        let shouldBeGreen = !isCollapsed || mouseInMenuBar
        targetDotAlpha = shouldBeGreen ? 1.0 : 0.0

        // If no animation running, start one
        if colorAnimTimer == nil {
            colorAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                let step: CGFloat = 0.04  // ~15 frames to transition = ~250ms
                if self.currentDotAlpha < self.targetDotAlpha {
                    self.currentDotAlpha = min(self.currentDotAlpha + step, self.targetDotAlpha)
                } else if self.currentDotAlpha > self.targetDotAlpha {
                    self.currentDotAlpha = max(self.currentDotAlpha - step, self.targetDotAlpha)
                }

                // Blend gray → green
                let r = self.grayColor.redComponent + (self.greenColor.redComponent - self.grayColor.redComponent) * self.currentDotAlpha
                let g = self.grayColor.greenComponent + (self.greenColor.greenComponent - self.grayColor.greenComponent) * self.currentDotAlpha
                let b = self.grayColor.blueComponent + (self.greenColor.blueComponent - self.grayColor.blueComponent) * self.currentDotAlpha
                let blended = NSColor(red: r, green: g, blue: b, alpha: 1.0)
                self.toggleItem.button?.image = self.makeDotImage(color: blended)

                // Stop when we've arrived
                if self.currentDotAlpha == self.targetDotAlpha {
                    timer.invalidate()
                    self.colorAnimTimer = nil
                }
            }
        }
    }

    // MARK: - Mouse Tracking

    private func setupMouseTracking() {
        // Use a timer to poll mouse location — works without Accessibility permissions
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.pollMouseLocation()
        }
    }

    private func pollMouseLocation() {
        let mouseLocation = NSEvent.mouseLocation  // screen coordinates (origin bottom-left)
        guard let screen = NSScreen.main else { return }
        // visibleFrame excludes the menu bar; the gap between frame.height and visibleFrame.maxY is the menu bar
        // visibleFrame.maxY is the bottom edge of the menu bar
        // Subtract a buffer so the entire menu bar area counts, not just the very top pixel
        let menuBarBottom = screen.visibleFrame.maxY - 25
        let inMenuBar = mouseLocation.y >= menuBarBottom
        if inMenuBar != mouseInMenuBar {
            mouseInMenuBar = inMenuBar
            updateDotColor()
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Clear any saved positions from previous versions to prevent reboot position swaps
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position mbb3-toggle")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position mbb3-separator")

        // Toggle (green dot) — rightmost, always visible
        if let button = toggleItem.button {
            button.image = makeDotImage(color: grayColor)
            button.imagePosition = .imageOnly
            button.title = ""
            button.target = self
            button.action = #selector(toggleItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Separator (thin line) — to the left of toggle
        if let button = separatorItem.button {
            button.title = "│"
            button.font = NSFont.systemFont(ofSize: 8, weight: .ultraLight)
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            button.attributedTitle = NSAttributedString(
                string: "│",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 8, weight: .ultraLight),
                    .foregroundColor: NSColor(white: 1.0, alpha: 0.3),
                    .paragraphStyle: style
                ]
            )
            button.target = self
            button.action = #selector(separatorClicked)
            button.sendAction(on: [.leftMouseUp])
        }

        // Start expanded
        separatorItem.length = expandedLength
        updateDotColor()
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

    @objc private func separatorClicked() {
        if isCollapsed {
            expandMenuBar()
        }
    }

    private func toggleMenuBar() {
        if isCollapsed {
            expandMenuBar()
        } else {
            collapseMenuBar()
        }
    }

    private func collapseMenuBar() {
        separatorItem.button?.attributedTitle = NSAttributedString(string: "")
        separatorItem.length = collapseLength
        updateDotColor()
    }

    private func expandMenuBar() {
        separatorItem.length = expandedLength
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        separatorItem.button?.attributedTitle = NSAttributedString(
            string: "│",
            attributes: [
                .font: NSFont.systemFont(ofSize: 8, weight: .ultraLight),
                .foregroundColor: NSColor(white: 1.0, alpha: 0.3),
                .paragraphStyle: style
            ]
        )
        updateDotColor()
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
        mouseTimer?.invalidate()
        NSApp.terminate(nil)
    }
}
