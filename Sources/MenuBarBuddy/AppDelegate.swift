import AppKit
import SwiftUI
import HotKey
import ServiceManagement
import ExceptionShield

class AppDelegate: NSObject, NSApplicationDelegate {
    // Created FIRST = rightmost = always visible (just like Hidden Bar's btnExpandCollapse)
    // (var, not let: the hosting watchdog can recreate them if the menu bar
    // host orphans them)
    private var toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    // Created SECOND = to the left of toggle = this expands (just like Hidden Bar's btnSeparate)
    private var separatorItem = NSStatusBar.system.statusItem(withLength: 1)

    private var settingsWindow: NSWindow?
    private var contextMenu: NSMenu!
    private var startAtLoginMenuItem: NSMenuItem?
    private var rainbowDotMenuItem: NSMenuItem?
    private var rainbowTimer: Timer?
    private var rainbowHue: CGFloat = 0.45  // start near the classic mint
    private var hotKey: HotKey?
    private var mouseMonitor: Any?
    private var mouseTimer: Timer?
    private var colorAnimTimer: Timer?
    private var currentDotAlpha: CGFloat = 0.0  // 0 = gray, 1 = green
    private var targetDotAlpha: CGFloat = 0.0
    private var sigtermSource: DispatchSourceSignal?
    private var sigintSource: DispatchSourceSignal?

    // Watchdog state (see pollMouseLocation)
    private var pollTick = 0
    private var misorderStreak = 0
    private var parkedStreak = 0
    private var hostingRecoveryAttempts = 0
    private var repairAlertShown = false

    private let settingsStore = SettingsStore.shared
    private var collapseLength: CGFloat = 2000
    private let expandedLength: CGFloat = 12

    // Preferred positions are distances from the screen's RIGHT edge, so a
    // smaller value means further right. The toggle must always stay to the
    // right of the separator (togglePos < separatorPos) or collapsing would
    // hide the toggle itself with no visible way back.
    private let togglePositionKey = "NSStatusItem Preferred Position mbb3-toggle"
    private let separatorPositionKey = "NSStatusItem Preferred Position mbb3-separator"

    // Dot colors
    private let greenColor = NSColor(red: 120/255, green: 230/255, blue: 200/255, alpha: 1.0)
    private let grayColor = NSColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1.0)
    private var mouseInMenuBar = false

    private var isCollapsed: Bool {
        return separatorItem.length > expandedLength
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second instance would register a duplicate set of status items.
        terminateIfDuplicateInstance()

        updateCollapseLength()
        setupUI()
        setupContextMenu()
        setupHotKey()
        setupMouseTracking()
        setupSignalHandlers()
        reassertStartAtLogin()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        if CommandLine.arguments.contains("--force-repair") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
                performSelfRepair()
            }
        }
        if CommandLine.arguments.contains("--test-collapse") {
            runCollapseTest()
        }
        if CommandLine.arguments.contains("--test-bounce") {
            setbuf(stdout, nil)
            func report(_ tag: String) {
                let tf = toggleItem.button?.window?.frame ?? .zero
                let sf = separatorItem.button?.window?.frame ?? .zero
                print("\(tag) toggle=\(Int(tf.origin.x)),\(Int(tf.origin.y)) \(Int(tf.width))w separ=\(Int(sf.origin.x)),\(Int(sf.origin.y)) \(Int(sf.width))w")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                report("before-bounce:")
                toggleItem.isVisible = false
                separatorItem.isVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                    toggleItem.isVisible = true
                    separatorItem.isVisible = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [self] in
                report("after-bounce:")
                quitApp()
            }
        }
        if CommandLine.arguments.contains("--rainbow-debug") {
            setbuf(stdout, nil)
            var tick = 0
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
                tick += 1
                print("t+\(tick)s rainbowOn=\(rainbowEnabled) timer=\(rainbowTimer != nil) collapsed=\(isCollapsed) mouseInBar=\(mouseInMenuBar) alpha=\(String(format: "%.2f", currentDotAlpha)) hue=\(String(format: "%.2f", rainbowHue)) len=\(Int(separatorItem.length))")
                if tick >= 12 { quitApp() }
            }
        }
        if CommandLine.arguments.contains("--dump-state") {
            setbuf(stdout, nil)
            var tick = 0
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
                tick += 1
                let tf = toggleItem.button?.window?.frame ?? .zero
                let sf = separatorItem.button?.window?.frame ?? .zero
                print("t+\(tick)s toggle: vis=\(toggleItem.isVisible) len=\(Int(toggleItem.length)) frame=\(Int(tf.origin.x)),\(Int(tf.origin.y)) \(Int(tf.width))x\(Int(tf.height)) onScreen=\(toggleItem.button?.window?.isOnActiveSpace ?? false)")
                print("t+\(tick)s separ:  vis=\(separatorItem.isVisible) len=\(Int(separatorItem.length)) frame=\(Int(sf.origin.x)),\(Int(sf.origin.y)) \(Int(sf.width))x\(Int(sf.height))")
                if tick >= 5 { quitApp() }
            }
        }
        if CommandLine.arguments.contains("--test-visual") {
            setbuf(stdout, nil)
            print("TEST: launched, collapsing in 4s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                collapseMenuBar()
                print("TEST: collapsed, length=\(Int(separatorItem.length)) readback frame=\(separatorItem.button?.window?.frame ?? .zero)")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [self] in
                expandMenuBar()
                print("TEST: expanded")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 16) { [self] in
                print("TEST: done")
                quitApp()
            }
        }
    }

    // MARK: - Lifecycle hardening

    private func terminateIfDuplicateInstance() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let myPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        if !others.isEmpty {
            NSApp.terminate(nil)
        }
    }

    /// Dying uncleanly while the menu bar host is touching one of our items is
    /// what gets the bundle ID blacklisted, so turn SIGTERM/SIGINT (pkill,
    /// Ctrl-C, logout) into a graceful expand-and-quit.
    private func setupSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource?.setEventHandler { [weak self] in self?.quitApp() }
        sigtermSource?.resume()
        sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource?.setEventHandler { [weak self] in self?.quitApp() }
        sigintSource?.resume()
    }

    // MARK: - Start at Login

    private var startAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// After a self-repair the bundle ID changes, which invalidates the old
    /// login item registration; re-register if the user had it on.
    private func reassertStartAtLogin() {
        guard UserDefaults.standard.bool(forKey: "MenuBarBuddy.startAtLogin"),
              !startAtLoginEnabled else { return }
        try? SMAppService.mainApp.register()
    }

    @objc private func toggleStartAtLogin() {
        do {
            if startAtLoginEnabled {
                try SMAppService.mainApp.unregister()
                UserDefaults.standard.set(false, forKey: "MenuBarBuddy.startAtLogin")
            } else {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: "MenuBarBuddy.startAtLogin")
            }
        } catch {
            NSLog("MenuBarBuddy: Start at Login toggle failed: \(error)")
        }
        startAtLoginMenuItem?.state = startAtLoginEnabled ? .on : .off
    }

    // MARK: - Debug test harness (--test-collapse)

    private func dumpStatusWindows(_ tag: String) {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return }
        let items = list.filter { ($0[kCGWindowLayer as String] as? Int) == 25 }
            .compactMap { w -> String? in
                guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
                let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
                return "\(owner)@x=\(Int(b["X"] ?? -1)),w=\(Int(b["Width"] ?? -1))"
            }
            .sorted()
        print("TEST[\(tag)] status windows: \(items.joined(separator: " | "))")
    }

    private func runCollapseTest() {
        setbuf(stdout, nil)
        let lengths: [CGFloat] = [12, 100, 500, 1000, 2000, 5000, 10000]
        print("TEST: macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("TEST: screen visibleFrame width = \(NSScreen.main?.visibleFrame.width ?? -1)")
        dumpStatusWindows("baseline")
        var delay: TimeInterval = 2
        for len in lengths {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                separatorItem.button?.attributedTitle = NSAttributedString(string: "")
                separatorItem.length = len
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                    let readback = separatorItem.length
                    let frame = separatorItem.button?.window?.frame ?? .zero
                    print("TEST: set=\(Int(len)) readback=\(Int(readback)) windowFrame=x:\(Int(frame.origin.x)) w:\(Int(frame.width))")
                    dumpStatusWindows("len\(Int(len))")
                }
            }
            delay += 1.2
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1) { [self] in
            print("TEST: done")
            quitApp()
        }
    }

    private func updateCollapseLength() {
        // macOS 26 (Tahoe) enforces a hard maximum of 10_000 on
        // NSStatusItem.length and throws NSInvalidArgumentException above it.
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1728
        collapseLength = min(10_000, max(500, screenWidth * 2.5 * CGFloat(settingsStore.pushMultiplier)))
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

    // MARK: - Rainbow dot (optional mode)

    private var rainbowEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "MenuBarBuddy.rainbowDot") }
        set { UserDefaults.standard.set(newValue, forKey: "MenuBarBuddy.rainbowDot") }
    }

    private func startRainbowIfNeeded() {
        guard rainbowTimer == nil else { return }
        colorAnimTimer?.invalidate()
        colorAnimTimer = nil
        rainbowTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.rainbowTick()
        }
    }

    private func stopRainbow() {
        rainbowTimer?.invalidate()
        rainbowTimer = nil
    }

    private func rainbowTick() {
        // Full hue cycle roughly every 8 seconds.
        rainbowHue = (rainbowHue + 0.05 / 8.0).truncatingRemainder(dividingBy: 1.0)
        // Same vividness rule as the classic dot: vivid when expanded or
        // hovered, grayed out when collapsed and idle. currentDotAlpha eases
        // between the two so state changes fade instead of snapping.
        let target: CGFloat = (!isCollapsed || mouseInMenuBar) ? 1.0 : 0.0
        let step: CGFloat = 0.06
        if currentDotAlpha < target {
            currentDotAlpha = min(currentDotAlpha + step, target)
        } else if currentDotAlpha > target {
            currentDotAlpha = max(currentDotAlpha - step, target)
        }
        let saturation = 0.15 + 0.75 * currentDotAlpha
        let brightness = 0.55 + 0.45 * currentDotAlpha
        let color = NSColor(hue: rainbowHue, saturation: saturation, brightness: brightness, alpha: 1.0)
        toggleItem.button?.image = makeDotImage(color: color)
    }

    @objc private func toggleRainbowDot() {
        rainbowEnabled.toggle()
        rainbowDotMenuItem?.state = rainbowEnabled ? .on : .off
        if !rainbowEnabled { stopRainbow() }
        updateDotColor()
    }

    private func updateDotColor() {
        if rainbowEnabled {
            startRainbowIfNeeded()
            return
        }
        stopRainbow()
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

        // Piggyback the watchdogs on this timer (0.15s ticks).
        pollTick += 1
        if pollTick % 20 == 0 {   // every ~3s: dot dragged into the hidden zone?
            checkLayoutOrder()
        }
        if pollTick % 34 == 0 {   // every ~5s: items still hosted by the menu bar?
            checkHosting()
        }
    }

    /// Proactive version of the collapse guard: if the user drops the dot
    /// inside the hidden zone, pop it back out within seconds instead of
    /// waiting for a doomed click. Two consecutive checks with no mouse button
    /// down, so we never fight an in-progress drag.
    private func checkLayoutOrder() {
        guard !isCollapsed, NSEvent.pressedMouseButtons == 0 else {
            misorderStreak = 0
            return
        }
        if layoutIsSafeToCollapse {
            misorderStreak = 0
        } else {
            misorderStreak += 1
            if misorderStreak >= 2 {
                misorderStreak = 0
                healLayout()
            }
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        // Without an autosaveName the items persist under generic "Item-0"/"Item-1"
        // keys. Tahoe's Control Center tracks visibility per key, and a crash can
        // leave the generic keys marked hidden, vanishing the items on relaunch.
        // Named keys sidestep that; forcing isVisible reasserts our own entry.
        // Positions are distances from the screen's right edge. Seed them from the
        // old bundle's layout (or sane defaults) so the separator sits left of the
        // toggle with the always-visible zone between; without a seed, fresh items
        // land at the far left of the status area with nothing left to hide.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: togglePositionKey) == nil {
            defaults.set(inheritedPosition(named: togglePositionKey, legacyKey: "NSStatusItem Preferred Position Item-0") ?? 230,
                         forKey: togglePositionKey)
        }
        if defaults.object(forKey: separatorPositionKey) == nil {
            defaults.set(inheritedPosition(named: separatorPositionKey, legacyKey: "NSStatusItem Preferred Position Item-1") ?? 388,
                         forKey: separatorPositionKey)
        }
        normalizeSavedPositions()
        bindStatusItems()
    }

    /// Everything needed to (re)wire the two status items: autosave binding,
    /// visibility, button config, expanded state. Shared between launch and
    /// the hosting watchdog's item recreation.
    private func bindStatusItems() {
        toggleItem.autosaveName = "mbb3-toggle"
        separatorItem.autosaveName = "mbb3-separator"
        toggleItem.isVisible = true
        separatorItem.isVisible = true

        configureToggleButton()      // green dot — rightmost, always visible
        configureSeparatorButton()   // thin line — left of toggle

        // Start expanded
        safelySetLength(expandedLength, on: separatorItem)
        updateDotColor()
    }

    /// Last-resort recovery when the menu bar host stops hosting our items:
    /// tear them down and register fresh ones in the original order.
    private func recreateStatusItems() {
        NSLog("MenuBarBuddy: recreating status items (hosting watchdog)")
        NSStatusBar.system.removeStatusItem(toggleItem)
        NSStatusBar.system.removeStatusItem(separatorItem)
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separatorItem = NSStatusBar.system.statusItem(withLength: 1)
        bindStatusItems()
    }

    private func configureToggleButton() {
        guard let button = toggleItem.button else { return }
        button.image = makeDotImage(color: grayColor)
        button.imagePosition = .imageOnly
        button.title = ""
        button.target = self
        button.action = #selector(toggleItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureSeparatorButton() {
        guard let button = separatorItem.button else { return }
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

        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = startAtLoginEnabled ? .on : .off
        contextMenu.addItem(loginItem)
        startAtLoginMenuItem = loginItem

        let rainbowItem = NSMenuItem(title: "Rainbow Dot", action: #selector(toggleRainbowDot), keyEquivalent: "")
        rainbowItem.target = self
        rainbowItem.state = rainbowEnabled ? .on : .off
        contextMenu.addItem(rainbowItem)
        rainbowDotMenuItem = rainbowItem

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
            startAtLoginMenuItem?.state = startAtLoginEnabled ? .on : .off
            rainbowDotMenuItem?.state = rainbowEnabled ? .on : .off
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

    // MARK: - Layout guard (the toggle must never sit inside the hidden zone)

    /// Look up a saved menu bar position in previous bundle IDs' domains so an
    /// ID bump keeps the user's arrangement. Recent domains use the same named
    /// key; the oldest used the auto-generated Item-N keys.
    private func inheritedPosition(named key: String, legacyKey: String) -> Double? {
        for domain in SettingsStore.previousBundleIDs {
            let lookup = domain == "com.menubarbuddy.app" ? legacyKey : key
            if let value = CFPreferencesCopyAppValue(lookup as CFString, domain as CFString) as? Double {
                return value
            }
        }
        return nil
    }

    /// Repair corrupt or unsafe saved positions before the items restore:
    /// non-finite/absurd values reset to seeds, and if the toggle would land
    /// at or left of the separator it is forced back to the far right.
    private func normalizeSavedPositions() {
        let defaults = UserDefaults.standard
        var togglePos = defaults.double(forKey: togglePositionKey)
        var separatorPos = defaults.double(forKey: separatorPositionKey)
        let isSane: (Double) -> Bool = { $0.isFinite && $0 >= 0 && $0 <= 5000 }
        if !isSane(togglePos) {
            togglePos = 230
            defaults.set(togglePos, forKey: togglePositionKey)
        }
        if !isSane(separatorPos) {
            separatorPos = 388
            defaults.set(separatorPos, forKey: separatorPositionKey)
        }
        if togglePos >= separatorPos {
            defaults.set(20, forKey: togglePositionKey)
            defaults.set(max(separatorPos, 80), forKey: separatorPositionKey)
        }
    }

    /// Distance from the right edge of the item's own screen, like the
    /// "NSStatusItem Preferred Position" defaults. Nil if the item has no window.
    private func liveDistanceFromRightEdge(_ item: NSStatusItem) -> CGFloat? {
        guard let window = item.button?.window, let screen = window.screen else { return nil }
        return screen.frame.maxX - window.frame.maxX
    }

    /// True when the toggle currently sits to the right of the separator.
    private var layoutIsSafeToCollapse: Bool {
        guard let togglePos = liveDistanceFromRightEdge(toggleItem),
              let separatorPos = liveDistanceFromRightEdge(separatorItem) else { return true }
        return togglePos < separatorPos
    }

    /// The user dragged the dot into the hidden zone, where collapsing would
    /// hide the toggle itself. Fix the saved position and re-insert the dot so
    /// it jumps back to the safe side. No relaunch: killing the process while
    /// the menu bar host is mid-manipulation is what gets the bundle ID
    /// blacklisted (see HANDOFF.md).
    private func healLayout() {
        UserDefaults.standard.set(20, forKey: togglePositionKey)
        toggleItem.isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            toggleItem.isVisible = true
            configureToggleButton()
            updateDotColor()
        }
    }

    /// Sets an NSStatusItem length behind the ObjC exception shield. macOS 26
    /// throws NSInvalidArgumentException above a system cap (10,000 today);
    /// if Apple ever lowers it, fall back through smaller values instead of
    /// dying mid-click with the UI half-toggled.
    @discardableResult
    private func safelySetLength(_ target: CGFloat, on item: NSStatusItem) -> Bool {
        for candidate in ([target, 5000, 2500, 1200].filter { $0 <= target }) {
            if MBBTryCatch({ item.length = candidate }) == nil {
                return true
            }
            NSLog("MenuBarBuddy: setting length \(Int(candidate)) threw; retrying smaller")
        }
        return false
    }

    private func collapseMenuBar() {
        guard layoutIsSafeToCollapse else {
            healLayout()
            return
        }
        // Tahoe clamps the drawn extent of status items that still have
        // content, which breaks the width-push. The expanded separator must be
        // a pure spacer: no title, no image, cell disabled (Ice does the same).
        if let button = separatorItem.button {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            button.image = nil
            button.cell?.isEnabled = false
            button.isHighlighted = false
        }
        guard safelySetLength(collapseLength, on: separatorItem) else {
            // Could not grow at any size; restore the expanded look so the UI
            // never shows a cleared separator that did nothing.
            expandMenuBar()
            return
        }
        updateDotColor()
        // Verify the push took: Tahoe has silently ignored large lengths
        // before. If the separator window never grew, undo cleanly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
            if isCollapsed, let window = separatorItem.button?.window, window.frame.width < 100 {
                NSLog("MenuBarBuddy: collapse did not take effect; reverting")
                expandMenuBar()
            }
        }
    }

    private func expandMenuBar() {
        separatorItem.button?.cell?.isEnabled = true
        safelySetLength(expandedLength, on: separatorItem)
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

    // MARK: - Hosting watchdog + self-repair

    /// Signature of the macOS 26 orphaning: the app runs, isVisible is true,
    /// but the items' windows are parked off-screen (y < 0), screenless, or
    /// crammed on top of each other at a display edge instead of being laid
    /// out in the menu bar.
    private func itemsLookOrphaned() -> Bool {
        // The toggle dot must be sanely hosted in EVERY state (only the
        // separator's geometry is intentionally weird while collapsed). This
        // must not skip collapsed state: an orphaned separator still accepts a
        // 10,000 length, so a blind-while-collapsed watchdog never fires.
        guard let toggleWindow = toggleItem.button?.window else { return true }
        if toggleWindow.screen == nil { return true }
        if toggleWindow.frame.origin.y < 0 { return true }
        guard !isCollapsed else { return false }
        guard let separatorWindow = separatorItem.button?.window else { return true }
        if separatorWindow.screen == nil { return true }
        if separatorWindow.frame.origin.y < 0 { return true }
        if toggleWindow.frame.intersects(separatorWindow.frame) { return true }
        return false
    }

    /// Escalating recovery: three consecutive positives (~15s) to rule out
    /// transient states, then recreate the items in-process (twice max), then
    /// offer the bundle-ID self-repair once.
    private func checkHosting() {
        guard itemsLookOrphaned() else {
            parkedStreak = 0
            return
        }
        parkedStreak += 1
        guard parkedStreak >= 3 else { return }
        parkedStreak = 0
        if hostingRecoveryAttempts < 2 {
            hostingRecoveryAttempts += 1
            recreateStatusItems()
        } else if !repairAlertShown {
            repairAlertShown = true
            showRepairAlert()
        }
    }

    private func showRepairAlert() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "MenuBarBuddy's icons are being blocked"
        alert.informativeText = "macOS blocked this copy of the app after an unclean shutdown (this happens if the app is force-killed while the menu bar is busy). Repair re-registers the app under a fresh identity and relaunches it. Your settings and icon positions are kept."
        alert.addButton(withTitle: "Repair and Relaunch")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        if response == .alertFirstButtonReturn {
            performSelfRepair()
        }
    }

    /// The blacklist is keyed on the bundle ID and survives relaunches and
    /// Control Center restarts; the only known escape is a fresh ID. Bump our
    /// own CFBundleIdentifier (v4 -> v5 -> ...), re-sign, and relaunch. The
    /// settings/position migration picks the old domain up automatically.
    private func performSelfRepair() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let bundlePath = Bundle.main.bundlePath
        let plistPath = bundlePath + "/Contents/Info.plist"
        guard let data = FileManager.default.contents(atPath: plistPath),
              var plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] else {
            NSLog("MenuBarBuddy: self-repair failed to read Info.plist")
            return
        }
        plist["CFBundleIdentifier"] = SettingsStore.nextBundleID(after: bundleID)
        guard let output = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
              (try? output.write(to: URL(fileURLWithPath: plistPath))) != nil else {
            NSLog("MenuBarBuddy: self-repair failed to write Info.plist")
            return
        }
        // Re-sign and relaunch after this process has fully exited (a running
        // binary cannot be re-signed in place).
        let script = "sleep 1; /usr/bin/codesign --force -s - \"\(bundlePath)\"; sleep 1; /usr/bin/open \"\(bundlePath)\""
        let relauncher = Process()
        relauncher.launchPath = "/bin/sh"
        relauncher.arguments = ["-c", script]
        try? relauncher.run()
        NSApp.terminate(nil)
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
