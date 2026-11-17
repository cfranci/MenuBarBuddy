import AppKit
import SwiftUI
import HotKey
import ServiceManagement
import ExceptionShield
import CoreImage

private extension NSColor {
    var hexString: String {
        guard let c = usingColorSpace(.deviceRGB) else { return "#808080" }
        return String(format: "#%02X%02X%02X",
                      Int(c.redComponent * 255),
                      Int(c.greenComponent * 255),
                      Int(c.blueComponent * 255))
    }
    convenience init?(hexString hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red:   CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8)  & 0xFF) / 255,
                  blue:  CGFloat(v & 0xFF) / 255,
                  alpha: 1.0)
    }
}

// MARK: - CollapseGroup

struct CollapseGroup {
    var color: NSColor
    var name: String

    static let defaults: [CollapseGroup] = [
        CollapseGroup(color: NSColor(red: 0.70, green: 0.40, blue: 0.90, alpha: 1.0), name: "Purple"),
        CollapseGroup(color: NSColor(red: 0.47, green: 0.90, blue: 0.78, alpha: 1.0), name: "Green"),
        CollapseGroup(color: NSColor(red: 0.95, green: 0.40, blue: 0.40, alpha: 1.0), name: "Red"),
    ]
}

// MARK: - Appearance enums

enum DotStyle: String, CaseIterable {
    case classic, rainbow, ocean, lava, aurora, custom

    var title: String {
        switch self {
        case .classic: return "Classic"
        case .rainbow: return "Rainbow"
        case .ocean:   return "Ocean"
        case .lava:    return "Lava"
        case .aurora:  return "Aurora"
        case .custom:  return "Custom Color…"
        }
    }

    var palette: (base: CGFloat, drift: CGFloat, offset: CGFloat) {
        switch self {
        case .ocean:  return (0.55, 0.07, 0.06)
        case .lava:   return (0.02, 0.05, 0.06)
        case .aurora: return (0.38, 0.08, 0.34)
        default:      return (0.45, 0.00, 0.33)
        }
    }
}

enum DotMotion: String, CaseIterable {
    case wave, ripple, spin, breathe, steady

    var title: String {
        switch self {
        case .wave:    return "Wave"
        case .ripple:  return "Ripple"
        case .spin:    return "Spin"
        case .breathe: return "Breathe"
        case .steady:  return "Steady"
        }
    }
}

enum DotSpeed: String, CaseIterable {
    case slow, normal, fast

    var title: String {
        switch self {
        case .slow:   return "Slow"
        case .normal: return "Normal"
        case .fast:   return "Fast"
        }
    }

    var multiplier: CGFloat {
        switch self {
        case .slow:   return 0.5
        case .normal: return 1.0
        case .fast:   return 2.0
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

    // Status items — created in applicationDidFinishLaunching in order:
    // toggleItem (1st = rightmost), then separators rightmost-first so that
    // separatorItems[0] ends up leftmost in the menu bar.
    private var toggleItem: NSStatusItem!
    private var separatorItems: [NSStatusItem] = []

    // Multi-group collapse state
    // currentStep = 0: fully expanded
    // currentStep = k (1..N): groups 0..(k-1) are hidden
    // currentStep = N: all groups hidden (nuclear)
    private var currentStep: Int = 0
    private var groups: [CollapseGroup] = []
    private var lastPressTime: Date = .distantPast
    private var lastClickTime: Date = .distantPast
    private let cycleTimeoutSeconds: TimeInterval = 60.0

    private var settingsWindow: NSWindow?
    private var contextMenu: NSMenu!
    private var startAtLoginMenuItem: NSMenuItem?
    private var appearanceMenu: NSMenu?
    private var rainbowTimer: Timer?
    private var rainbowHue: CGFloat = 0.45
    private var rainbowWavePhase: CGFloat = 0
    private var palettePhase: CGFloat = 0
    private var hotKey: HotKey?
    private var mouseMonitor: Any?
    private var mouseTimer: Timer?
    private var colorAnimTimer: Timer?
    private var collapseStepTimer: Timer?
    private var coverPanel: NSPanel?
    private let barHider = MBBarHider()

    private var currentDotAlpha: CGFloat = 0.0
    private var targetDotAlpha: CGFloat = 0.0
    private var sigtermSource: DispatchSourceSignal?
    private var sigintSource: DispatchSourceSignal?

    private var pollTick = 0
    private var misorderStreak = 0
    private var parkedStreak = 0
    private var hostingRecoveryAttempts = 0
    private var repairAlertShown = false
    private var watchdogGraceUntil = Date.distantPast
    private var screensAsleep = false
    private var sessionLocked = false
    private var lastHostingRecoveryAt = Date.distantPast

    private let settingsStore = SettingsStore.shared
    private var collapseLength: CGFloat = 2000
    private let expandedLength: CGFloat = 12

    // Position keys — distances from screen right edge
    private let togglePositionKey   = "NSStatusItem Preferred Position mbb3-toggle"
    private let sep0PositionKey     = "NSStatusItem Preferred Position mbb3-sep-0"
    private let sep1PositionKey     = "NSStatusItem Preferred Position mbb3-sep-1"
    private let sep2PositionKey     = "NSStatusItem Preferred Position mbb3-sep-2"

    // Dot colors (classic mode)
    private let grayColor = NSColor(red: 0.45, green: 0.45, blue: 0.45, alpha: 1.0)
    private var mouseInMenuBar = false

    private var isCollapsed: Bool { currentStep > 0 }

    private var showSeparatorLines: Bool {
        get {
            return UserDefaults.standard.object(forKey: "MenuBarBuddy.showLines") == nil
                ? true
                : UserDefaults.standard.bool(forKey: "MenuBarBuddy.showLines")
        }
        set { UserDefaults.standard.set(newValue, forKey: "MenuBarBuddy.showLines") }
    }
    private var hideSystemClock: Bool {
        get { UserDefaults.standard.bool(forKey: "MenuBarBuddy.hideSystemClock") }
        set { UserDefaults.standard.set(newValue, forKey: "MenuBarBuddy.hideSystemClock") }
    }
    private var hideControlCenter: Bool {
        get { UserDefaults.standard.bool(forKey: "MenuBarBuddy.hideControlCenter") }
        set { UserDefaults.standard.set(newValue, forKey: "MenuBarBuddy.hideControlCenter") }
    }
    private var showLinesMenuItem: NSMenuItem?
    private var hideClockMenuItem: NSMenuItem?
    private var hideCCMenuItem: NSMenuItem?

    // The rightmost group's color drives the dot in classic mode
    private var activeDotColor: NSColor {
        groups.last?.color ?? NSColor(red: 120/255, green: 230/255, blue: 200/255, alpha: 1.0)
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateIfDuplicateInstance()

        // Request Accessibility access so we can read menu bar item positions
        // via AXUIElement (kAXExtrasMenuBarAttribute). Without this, partial
        // collapses fall back to allowing all apps (groups don't hide selectively).
        mbbLog("MBB launch: AXIsProcessTrusted=\(AXIsProcessTrusted())")
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        }

        groups = loadGroups()
        if UserDefaults.standard.array(forKey: "MenuBarBuddy.groups") == nil {
            saveGroups()
        }

        // Create status items in the correct order: toggle first (rightmost),
        // then separators rightmost-to-leftmost (using insert-at-0 so
        // separatorItems[0] = leftmost, separatorItems[N-1] = rightmost).
        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        for _ in 0..<groups.count {
            separatorItems.insert(NSStatusBar.system.statusItem(withLength: 1), at: 0)
        }

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
        setupWatchdogSuppression()

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
                let sf = separatorItems.first?.button?.window?.frame ?? .zero
                print("\(tag) toggle=\(Int(tf.origin.x)),\(Int(tf.origin.y)) \(Int(tf.width))w separ=\(Int(sf.origin.x)),\(Int(sf.origin.y)) \(Int(sf.width))w")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                report("before-bounce:")
                toggleItem.isVisible = false
                for item in separatorItems { item.isVisible = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                    toggleItem.isVisible = true
                    for item in separatorItems { item.isVisible = true }
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
                print("t+\(tick)s rainbowOn=\(rainbowEnabled) timer=\(rainbowTimer != nil) collapsed=\(isCollapsed) mouseInBar=\(mouseInMenuBar) alpha=\(String(format: "%.2f", currentDotAlpha)) hue=\(String(format: "%.2f", rainbowHue)) len=\(Int(separatorItems.first?.length ?? 0))")
                if tick >= 12 { quitApp() }
            }
        }
        if CommandLine.arguments.contains("--dump-state") {
            setbuf(stdout, nil)
            var tick = 0
            Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
                tick += 1
                let tf = toggleItem.button?.window?.frame ?? .zero
                let sf = separatorItems.first?.button?.window?.frame ?? .zero
                print("t+\(tick)s toggle: vis=\(toggleItem.isVisible) len=\(Int(toggleItem.length)) frame=\(Int(tf.origin.x)),\(Int(tf.origin.y)) \(Int(tf.width))x\(Int(tf.height))")
                print("t+\(tick)s sep[0]: vis=\(separatorItems.first?.isVisible ?? false) len=\(Int(separatorItems.first?.length ?? 0)) frame=\(Int(sf.origin.x)),\(Int(sf.origin.y)) \(Int(sf.width))x\(Int(sf.height))")
                if tick >= 5 { quitApp() }
            }
        }
        if CommandLine.arguments.contains("--test-visual") {
            setbuf(stdout, nil)
            print("TEST: launched, collapsing in 4s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                collapseMenuBar(step: 1)
                print("TEST: collapse started, len=\(Int(separatorItems.first?.length ?? 0))")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [self] in
                let frame = separatorItems.first?.button?.window?.frame ?? .zero
                print("TEST: collapsed frame=\(frame) isCollapsed=\(isCollapsed) step=\(currentStep)")
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

    // MARK: - Show Lines / System Items toggles

    @objc private func toggleShowLines() {
        showSeparatorLines = !showSeparatorLines
        showLinesMenuItem?.state = showSeparatorLines ? .on : .off
        updateSeparatorVisibility()
    }

    @objc private func toggleHideClock() {
        hideSystemClock = !hideSystemClock
        hideClockMenuItem?.state = hideSystemClock ? .on : .off
    }

    @objc private func toggleHideCC() {
        hideControlCenter = !hideControlCenter
        hideCCMenuItem?.state = hideControlCenter ? .on : .off
    }

    // MARK: - Group persistence

    private func saveGroups() {
        let dicts = groups.map { ["name": $0.name, "hex": $0.color.hexString] }
        UserDefaults.standard.set(dicts, forKey: "MenuBarBuddy.groups")
    }

    private func loadGroups() -> [CollapseGroup] {
        guard let saved = UserDefaults.standard.array(forKey: "MenuBarBuddy.groups") as? [[String: String]] else {
            return CollapseGroup.defaults
        }
        let loaded = saved.compactMap { d -> CollapseGroup? in
            guard let name = d["name"],
                  let hex = d["hex"],
                  let color = NSColor(hexString: hex) else { return nil }
            return CollapseGroup(color: color, name: name)
        }
        return loaded.isEmpty ? CollapseGroup.defaults : loaded
    }

    // Clock = com.apple.MenuBarAgent, CC = com.apple.controlcenter.
    // We hide them by omitting their bundle IDs from allowedBundleIdentifiers;
    // allowedSystemItems is always unrestricted (empty = all system items shown).
    private static let clockBundleID = "com.apple.MenuBarAgent"
    private static let ccBundleID    = "com.apple.controlcenter"

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
        let sep = separatorItems[0]
        var delay: TimeInterval = 2
        for len in lengths {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
                sep.button?.attributedTitle = NSAttributedString(string: "")
                sep.length = len
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                    let readback = sep.length
                    let frame = sep.button?.window?.frame ?? .zero
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
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1728
        collapseLength = min(10_000, max(500, screenWidth * 2.5 * CGFloat(settingsStore.pushMultiplier)))
    }

    @objc private func screenChanged() {
        updateCollapseLength()
        deferWatchdog(seconds: 60)
    }

    private func setupWatchdogSuppression() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(screensDidSleep),
                              name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.screensDidWakeNotification, object: nil)
        workspace.addObserver(self, selector: #selector(screensDidWake),
                              name: NSWorkspace.didWakeNotification, object: nil)
        let dist = DistributedNotificationCenter.default()
        dist.addObserver(self, selector: #selector(sessionLockedNotification),
                         name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        dist.addObserver(self, selector: #selector(sessionUnlockedNotification),
                         name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    private func deferWatchdog(seconds: TimeInterval) {
        watchdogGraceUntil = max(watchdogGraceUntil, Date().addingTimeInterval(seconds))
        parkedStreak = 0
        misorderStreak = 0
    }

    @objc private func screensDidSleep() { screensAsleep = true; parkedStreak = 0 }
    @objc private func screensDidWake()  { screensAsleep = false; deferWatchdog(seconds: 60) }
    @objc private func sessionLockedNotification()   { sessionLocked = true; parkedStreak = 0 }
    @objc private func sessionUnlockedNotification() { sessionLocked = false; deferWatchdog(seconds: 30) }

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

    // Single colored | line — used for the leftmost visible separator
    private func makeLeftSeparatorImage(color: NSColor, height: CGFloat = 18) -> NSImage {
        let width: CGFloat = 6
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        let barWidth: CGFloat = 1.5
        let barHeight: CGFloat = 12
        let x = (width - barWidth) / 2
        let y = (height - barHeight) / 2
        let rect = NSRect(x: x, y: y, width: barWidth, height: barHeight)
        color.withAlphaComponent(0.70).setFill()
        NSBezierPath(roundedRect: rect, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // Double colored || line — used for separators between two visible groups
    private func makeDoubleSeparatorImage(leftColor: NSColor, rightColor: NSColor, height: CGFloat = 18) -> NSImage {
        let width: CGFloat = 10
        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        let barWidth: CGFloat = 1.5
        let barHeight: CGFloat = 12
        let gap: CGFloat = 2.5
        let totalW = barWidth * 2 + gap
        let startX = (width - totalW) / 2
        let y = (height - barHeight) / 2
        leftColor.withAlphaComponent(0.70).setFill()
        NSBezierPath(roundedRect: NSRect(x: startX, y: y, width: barWidth, height: barHeight),
                     xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        rightColor.withAlphaComponent(0.70).setFill()
        NSBezierPath(roundedRect: NSRect(x: startX + barWidth + gap, y: y, width: barWidth, height: barHeight),
                     xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // Two-tone animated dot
    private func makeStyledDotImage(topColor: NSColor, bottomColor: NSColor, wavePhase: CGFloat,
                                    motions: Set<DotMotion>, size: CGFloat = 18) -> NSImage {
        let scale: CGFloat = 2
        let px = Int(size * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let top = topColor.usingColorSpace(.deviceRGB),
              let bottom = bottomColor.usingColorSpace(.deviceRGB),
              let bytes = rep.bitmapData else {
            return makeDotImage(color: topColor, size: size)
        }
        var dotRadius = 4.5 * scale
        if motions.contains(.breathe) {
            dotRadius *= 0.88 + 0.12 * sin(wavePhase)
        }
        let center = CGFloat(px) / 2
        let amplitude = dotRadius * 0.35
        let blendBand = dotRadius * 0.9
        let bytesPerRow = rep.bytesPerRow
        let (tr, tg, tb) = (top.redComponent, top.greenComponent, top.blueComponent)
        let (br, bg, bb) = (bottom.redComponent, bottom.greenComponent, bottom.blueComponent)
        for y in 0..<px {
            for x in 0..<px {
                let dx = CGFloat(x) + 0.5 - center
                let dy = CGFloat(y) + 0.5 - center
                let dist = (dx * dx + dy * dy).squareRoot()
                let alpha = max(0, min(1, dotRadius - dist + 0.5))
                let offset = y * bytesPerRow + x * 4
                if alpha <= 0 {
                    bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0; bytes[offset + 3] = 0
                    continue
                }
                var components: [CGFloat] = []
                if motions.contains(.wave) {
                    let wave = amplitude * sin((dx / dotRadius) * .pi * 1.4 + wavePhase)
                    var tw = (dy - wave) / blendBand + 0.5
                    tw = max(0, min(1, tw))
                    components.append(tw * tw * (3 - 2 * tw))
                }
                if motions.contains(.ripple) {
                    components.append(0.5 + 0.5 * sin((dist / dotRadius) * .pi * 2.2 - wavePhase * 2))
                }
                if motions.contains(.spin) {
                    components.append(0.5 + 0.5 * sin(atan2(dy, dx) + wavePhase))
                }
                if motions.contains(.steady) {
                    var ts = dy / blendBand + 0.5
                    ts = max(0, min(1, ts))
                    components.append(ts * ts * (3 - 2 * ts))
                }
                let t = components.isEmpty ? 0 : components.reduce(0, +) / CGFloat(components.count)
                let r = tr + (br - tr) * t
                let g = tg + (bg - tg) * t
                let b = tb + (bb - tb) * t
                bytes[offset]     = UInt8(r * alpha * 255)
                bytes[offset + 1] = UInt8(g * alpha * 255)
                bytes[offset + 2] = UInt8(b * alpha * 255)
                bytes[offset + 3] = UInt8(alpha * 255)
            }
        }
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }

    // MARK: - Appearance

    private var rainbowEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "MenuBarBuddy.rainbowDot") }
        set { UserDefaults.standard.set(newValue, forKey: "MenuBarBuddy.rainbowDot") }
    }

    private var dotStyle: DotStyle {
        get {
            if let raw = UserDefaults.standard.string(forKey: "MenuBarBuddy.dotStyle"),
               let style = DotStyle(rawValue: raw) {
                return style
            }
            return rainbowEnabled ? .rainbow : .classic
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "MenuBarBuddy.dotStyle")
            rainbowEnabled = newValue != .classic
        }
    }

    private var dotMotions: Set<DotMotion> {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "MenuBarBuddy.dotMotion") else { return [.wave] }
            return Set(raw.split(separator: ",").compactMap { DotMotion(rawValue: String($0)) })
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted().joined(separator: ","),
                                      forKey: "MenuBarBuddy.dotMotion")
        }
    }

    private var dotSpeed: DotSpeed {
        get {
            guard let raw = UserDefaults.standard.string(forKey: "MenuBarBuddy.dotSpeed"),
                  let speed = DotSpeed(rawValue: raw) else { return .normal }
            return speed
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "MenuBarBuddy.dotSpeed") }
    }

    private var customDotHue: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: "MenuBarBuddy.customDotHue")
            return saved > 0 ? CGFloat(saved) : 0.75
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: "MenuBarBuddy.customDotHue") }
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
        let speed = dotSpeed.multiplier
        let style = dotStyle
        rainbowHue = (rainbowHue + speed * 0.05 / 8.0).truncatingRemainder(dividingBy: 1.0)
        palettePhase = (palettePhase + speed * 0.05 * 2 * .pi / 10).truncatingRemainder(dividingBy: 2 * .pi)
        let target: CGFloat = (!isCollapsed || mouseInMenuBar) ? 1.0 : 0.0
        let step: CGFloat = 0.06
        if currentDotAlpha < target {
            currentDotAlpha = min(currentDotAlpha + step, target)
        } else if currentDotAlpha > target {
            currentDotAlpha = max(currentDotAlpha - step, target)
        }
        let saturation = 0.15 + 0.75 * currentDotAlpha
        let brightness = 0.55 + 0.45 * currentDotAlpha
        rainbowWavePhase = (rainbowWavePhase + speed * 0.05 * 2 * .pi / 4).truncatingRemainder(dividingBy: 2 * .pi)

        let topHue: CGFloat
        let bottomHue: CGFloat
        switch style {
        case .rainbow:
            topHue = rainbowHue
            bottomHue = (rainbowHue + 0.33).truncatingRemainder(dividingBy: 1.0)
        case .custom:
            let base = customDotHue
            topHue = (base + 0.03 * sin(palettePhase) + 1).truncatingRemainder(dividingBy: 1.0)
            bottomHue = (base + 0.08 + 1).truncatingRemainder(dividingBy: 1.0)
        default:
            let p = style.palette
            topHue = (p.base + p.drift * sin(palettePhase) + 1).truncatingRemainder(dividingBy: 1.0)
            bottomHue = (topHue + p.offset).truncatingRemainder(dividingBy: 1.0)
        }
        let topColor = NSColor(hue: topHue, saturation: saturation, brightness: brightness, alpha: 1.0)
        let bottomColor = NSColor(hue: bottomHue, saturation: saturation, brightness: brightness, alpha: 1.0)
        toggleItem.button?.image = makeStyledDotImage(topColor: topColor, bottomColor: bottomColor,
                                                      wavePhase: rainbowWavePhase, motions: dotMotions)
    }

    @objc private func selectDotStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let style = DotStyle(rawValue: raw) else { return }
        if style == .custom { openCustomColorPanel() }
        dotStyle = style
        refreshAppearanceMenu()
        updateDotColor()
    }

    @objc private func selectDotMotion(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let motion = DotMotion(rawValue: raw) else { return }
        var set = dotMotions
        if set.contains(motion) { set.remove(motion) } else { set.insert(motion) }
        dotMotions = set
        refreshAppearanceMenu()
        updateDotColor()
    }

    @objc private func selectDotSpeed(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let speed = DotSpeed(rawValue: raw) else { return }
        dotSpeed = speed
        refreshAppearanceMenu()
        updateDotColor()
    }

    private func openCustomColorPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.mode = .wheel
        panel.color = NSColor(hue: customDotHue, saturation: 0.9, brightness: 1.0, alpha: 1.0)
        panel.setTarget(self)
        panel.setAction(#selector(customColorChanged(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func customColorChanged(_ sender: NSColorPanel) {
        guard let color = sender.color.usingColorSpace(.deviceRGB) else { return }
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        color.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
        customDotHue = hue
        if dotStyle != .custom {
            dotStyle = .custom
            refreshAppearanceMenu()
        }
        updateDotColor()
    }

    private func updateDotColor() {
        if dotStyle != .classic {
            startRainbowIfNeeded()
            return
        }
        stopRainbow()
        let shouldBeActive = !isCollapsed || mouseInMenuBar
        targetDotAlpha = shouldBeActive ? 1.0 : 0.0

        if colorAnimTimer == nil {
            colorAnimTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                let step: CGFloat = 0.04
                if self.currentDotAlpha < self.targetDotAlpha {
                    self.currentDotAlpha = min(self.currentDotAlpha + step, self.targetDotAlpha)
                } else if self.currentDotAlpha > self.targetDotAlpha {
                    self.currentDotAlpha = max(self.currentDotAlpha - step, self.targetDotAlpha)
                }
                let active = self.activeDotColor
                let r = self.grayColor.redComponent   + (active.redComponent   - self.grayColor.redComponent)   * self.currentDotAlpha
                let g = self.grayColor.greenComponent + (active.greenComponent - self.grayColor.greenComponent) * self.currentDotAlpha
                let b = self.grayColor.blueComponent  + (active.blueComponent  - self.grayColor.blueComponent)  * self.currentDotAlpha
                let blended = NSColor(red: r, green: g, blue: b, alpha: 1.0)
                self.toggleItem.button?.image = self.makeDotImage(color: blended)

                if self.currentDotAlpha == self.targetDotAlpha {
                    timer.invalidate()
                    self.colorAnimTimer = nil
                }
            }
        }
    }

    // MARK: - Mouse Tracking

    private func setupMouseTracking() {
        mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.pollMouseLocation()
        }
    }

    private func pollMouseLocation() {
        let mouseLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { return }
        let menuBarBottom = screen.visibleFrame.maxY - 25
        let inMenuBar = mouseLocation.y >= menuBarBottom
        if inMenuBar != mouseInMenuBar {
            mouseInMenuBar = inMenuBar
            updateDotColor()
        }

        pollTick += 1
        if pollTick % 20 == 0 { checkLayoutOrder() }
        if pollTick % 34 == 0 { checkHosting() }
    }

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
        let defaults = UserDefaults.standard
        // Seed toggle position
        if defaults.object(forKey: togglePositionKey) == nil {
            defaults.set(inheritedPosition(named: togglePositionKey, legacyKey: "NSStatusItem Preferred Position Item-0") ?? 230,
                         forKey: togglePositionKey)
        }
        // Seed separator positions (first launch only). Use wide spread so
        // separators land in the app-icon zone, not crammed near the toggle.
        // sep0 = leftmost (all icons), sep1 = middle split, sep2 = right split.
        let sepKeys: [(String, Double, String?)] = [
            (sep0PositionKey, 2000, "NSStatusItem Preferred Position mbb3-separator"),
            (sep1PositionKey, 1200, nil),
            (sep2PositionKey, 500,  nil),
        ]
        for (key, defaultVal, legacyKey) in sepKeys {
            if defaults.object(forKey: key) == nil {
                var inherited: Double? = nil
                if let lk = legacyKey {
                    inherited = inheritedPosition(named: lk, legacyKey: "NSStatusItem Preferred Position Item-1")
                    // If the inherited position is too small (< 400) it was from the
                    // old single-sep setup near the toggle — ignore it.
                    if let v = inherited, v < 400 { inherited = nil }
                }
                defaults.set(inherited ?? defaultVal, forKey: key)
            }
        }
        defaults.synchronize()
        normalizeSavedPositions()
        bindStatusItems()
    }

    private func bindStatusItems() {
        let defaults = UserDefaults.standard
        let sepNames = ["mbb3-sep-0", "mbb3-sep-1", "mbb3-sep-2"]

        defaults.removeObject(forKey: "NSStatusItem VisibleCC mbb3-toggle")
        for name in sepNames {
            defaults.removeObject(forKey: "NSStatusItem VisibleCC \(name)")
        }

        toggleItem.isVisible = true
        toggleItem.autosaveName = "mbb3-toggle"

        for (i, item) in separatorItems.enumerated() {
            item.autosaveName = i < sepNames.count ? sepNames[i] : "mbb3-sep-\(i)"
            item.isVisible = true
        }

        configureToggleButton()
        for (i, item) in separatorItems.enumerated() {
            configureSeparatorItem(item, at: i)
        }

        safelySetLength(expandedLength, on: separatorItems[0])
        updateSeparatorVisibility()
        updateDotColor()
    }

    private func recreateStatusItems() {
        NSLog("MenuBarBuddy: recreating status items (hosting watchdog)")
        NSStatusBar.system.removeStatusItem(toggleItem)
        for item in separatorItems { NSStatusBar.system.removeStatusItem(item) }
        separatorItems = []

        toggleItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        for _ in 0..<groups.count {
            separatorItems.insert(NSStatusBar.system.statusItem(withLength: 1), at: 0)
        }
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

    private func configureSeparatorItem(_ item: NSStatusItem, at index: Int) {
        guard let button = item.button else { return }
        button.title = ""
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(separatorClicked)
        button.sendAction(on: [.leftMouseUp])
    }

    // Separators sorted leftmost-to-rightmost by their actual screen x position.
    // Falls back to ascending array-index order if windows aren't ready yet.
    private func physicallyOrderedSeparators() -> [(index: Int, item: NSStatusItem)] {
        let pairs = separatorItems.enumerated().map { (index: $0.offset, item: $0.element) }
        guard pairs.allSatisfy({ $0.item.button?.window != nil }) else { return pairs }
        return pairs.sorted { $0.item.button!.window!.frame.minX < $1.item.button!.window!.frame.minX }
    }

    // Rerender all visible separators according to currentStep
    private func updateSeparatorVisibility() {
        // Step 1: mark hidden / visible
        var visible: [(index: Int, item: NSStatusItem)] = []
        for (i, item) in separatorItems.enumerated() {
            let hide = i < currentStep || (currentStep == 0 && (!showSeparatorLines || i == 0))
            item.isVisible = !hide
            if !hide { visible.append((index: i, item: item)) }
        }
        guard !visible.isEmpty else { return }

        // Step 2: sort by physical left-to-right position so rendering matches the bar
        if visible.allSatisfy({ $0.item.button?.window != nil }) {
            visible.sort { $0.item.button!.window!.frame.minX < $1.item.button!.window!.frame.minX }
        }

        // Step 3: render
        // Single | ONLY when collapsed and this is the physically-leftmost visible sep
        // (marks the hidden-to-visible boundary). In expanded state all show ||.
        for (rank, (i, item)) in visible.enumerated() {
            if rank == 0 && currentStep > 0 {
                // Leftmost visible while collapsed → boundary marker
                item.button?.image = makeLeftSeparatorImage(color: groups[i].color)
                item.length = 8
            } else {
                // Double || — sep i sits between group (i-1) and group i logically
                let leftColorIdx = i > 0 ? i - 1 : 0
                item.button?.image = makeDoubleSeparatorImage(
                    leftColor: groups[leftColorIdx].color,
                    rightColor: groups[i].color
                )
                item.length = 12
            }
            item.button?.imagePosition = .imageOnly
            item.button?.title = ""
        }
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

        let showLinesItem = NSMenuItem(title: "Show Lines", action: #selector(toggleShowLines), keyEquivalent: "")
        showLinesItem.target = self
        showLinesItem.state = showSeparatorLines ? .on : .off
        contextMenu.addItem(showLinesItem)
        showLinesMenuItem = showLinesItem

        let systemItem = NSMenuItem(title: "System Items", action: nil, keyEquivalent: "")
        let systemMenu = NSMenu()
        let clockItem = NSMenuItem(title: "Hide Clock", action: #selector(toggleHideClock), keyEquivalent: "")
        clockItem.target = self
        clockItem.state = hideSystemClock ? .on : .off
        systemMenu.addItem(clockItem)
        hideClockMenuItem = clockItem
        let ccItem = NSMenuItem(title: "Hide Control Center", action: #selector(toggleHideCC), keyEquivalent: "")
        ccItem.target = self
        ccItem.state = hideControlCenter ? .on : .off
        systemMenu.addItem(ccItem)
        hideCCMenuItem = ccItem
        systemItem.submenu = systemMenu
        contextMenu.addItem(systemItem)

        let appearanceItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        func addHeader(_ title: String) {
            let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)
        }
        addHeader("Style")
        for style in DotStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(selectDotStyle(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            submenu.addItem(item)
        }
        submenu.addItem(NSMenuItem.separator())
        addHeader("Motion — stack any")
        for motion in DotMotion.allCases {
            let item = NSMenuItem(title: motion.title, action: #selector(selectDotMotion(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = motion.rawValue
            submenu.addItem(item)
        }
        submenu.addItem(NSMenuItem.separator())
        addHeader("Speed")
        for speed in DotSpeed.allCases {
            let item = NSMenuItem(title: speed.title, action: #selector(selectDotSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed.rawValue
            submenu.addItem(item)
        }
        appearanceItem.submenu = submenu
        contextMenu.addItem(appearanceItem)
        appearanceMenu = submenu
        refreshAppearanceMenu()

        contextMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit MenuBarBuddy", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        contextMenu.addItem(quitItem)
    }

    private func refreshAppearanceMenu() {
        guard let submenu = appearanceMenu else { return }
        for item in submenu.items {
            guard let raw = item.representedObject as? String else { continue }
            let isOn: Bool
            switch item.action {
            case #selector(selectDotStyle(_:)):  isOn = raw == dotStyle.rawValue
            case #selector(selectDotMotion(_:)): isOn = DotMotion(rawValue: raw).map(dotMotions.contains) ?? false
            case #selector(selectDotSpeed(_:)):  isOn = raw == dotSpeed.rawValue
            default: isOn = false
            }
            item.state = isOn ? .on : .off
        }
    }

    private func updateContextMenuTitle() {
        let title: String
        if currentStep == 0 {
            title = "Hide Menu Bar"
        } else if currentStep < groups.count {
            title = "Hide More"
        } else {
            title = "Expand Menu Bar"
        }
        if contextMenu.items.isEmpty {
            let item = NSMenuItem(title: title, action: #selector(toggleMenuBarAction), keyEquivalent: "")
            item.target = self
            contextMenu.insertItem(item, at: 0)
        } else {
            contextMenu.items[0].title = title
        }
    }

    @objc private func toggleItemClicked(_ sender: Any?) {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
        if isRightClick {
            updateContextMenuTitle()
            startAtLoginMenuItem?.state = startAtLoginEnabled ? .on : .off
            showLinesMenuItem?.state = showSeparatorLines ? .on : .off
            hideClockMenuItem?.state = hideSystemClock ? .on : .off
            hideCCMenuItem?.state = hideControlCenter ? .on : .off
            refreshAppearanceMenu()
            toggleItem.menu = contextMenu
            toggleItem.button?.performClick(nil)
            toggleItem.menu = nil
        } else {
            toggleMenuBar()
        }
    }

    @objc private func toggleMenuBarAction() { toggleMenuBar() }

    @objc private func separatorClicked() {
        if isCollapsed { expandMenuBar() }
    }

    // MARK: - Collapse cycle

    private func toggleMenuBar() {
        let now = Date()

        // Double-click within 0.4s: collapse all or expand all
        if now.timeIntervalSince(lastClickTime) < 0.4 {
            lastClickTime = .distantPast
            if currentStep > 0 {
                expandMenuBar()
            } else {
                collapseMenuBar(step: groups.count)
            }
            return
        }
        lastClickTime = now

        let timeSinceLast = now.timeIntervalSince(lastPressTime)
        lastPressTime = now

        // Time-based reset: if bar is partially/fully collapsed and idle > 60s,
        // the next press expands rather than advancing
        if currentStep > 0 && timeSinceLast > cycleTimeoutSeconds {
            expandMenuBar()
            return
        }

        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

        if currentStep < groups.count {
            let nextStep = currentStep + 1
            if major >= 26 {
                collapseViaAssessmentMode(step: nextStep)
            } else {
                currentStep = nextStep
                collapseViaLengthPush()
            }
        } else {
            expandMenuBar()
        }
    }

    // MARK: - Layout guard

    private func inheritedPosition(named key: String, legacyKey: String) -> Double? {
        for domain in SettingsStore.previousBundleIDs {
            let lookup = domain == "com.menubarbuddy.app" ? legacyKey : key
            if let value = CFPreferencesCopyAppValue(lookup as CFString, domain as CFString) as? Double {
                return value
            }
        }
        return nil
    }

    private func normalizeSavedPositions() {
        let defaults = UserDefaults.standard
        var togglePos = defaults.double(forKey: togglePositionKey)
        var sep2Pos   = defaults.double(forKey: sep2PositionKey)
        var sep1Pos   = defaults.double(forKey: sep1PositionKey)
        var sep0Pos   = defaults.double(forKey: sep0PositionKey)

        let isSane: (Double) -> Bool = { $0.isFinite && $0 >= 0 && $0 <= 10000 }
        if !isSane(togglePos) { togglePos = 230;  defaults.set(togglePos, forKey: togglePositionKey) }
        if !isSane(sep2Pos)   { sep2Pos   = 500;  defaults.set(sep2Pos,   forKey: sep2PositionKey) }
        if !isSane(sep1Pos)   { sep1Pos   = 1200; defaults.set(sep1Pos,   forKey: sep1PositionKey) }
        if !isSane(sep0Pos)   { sep0Pos   = 2000; defaults.set(sep0Pos,   forKey: sep0PositionKey) }

        // If all three separators are clustered close together (< 800 apart in total),
        // they were likely seeded from the old close-to-toggle defaults (350/500/650).
        // Force-reset to a wide spread so they land in the actual icon zone.
        if sep0Pos - sep2Pos < 800 && sep0Pos < 2500 {
            sep0Pos = 2000; sep1Pos = 1200; sep2Pos = 500
            defaults.set(sep0Pos, forKey: sep0PositionKey)
            defaults.set(sep1Pos, forKey: sep1PositionKey)
            defaults.set(sep2Pos, forKey: sep2PositionKey)
        }

        // Ensure toggle < sep2 < sep1 < sep0 (larger = further left)
        if togglePos >= sep2Pos {
            defaults.set(20, forKey: togglePositionKey)
        }
        if sep2Pos >= sep1Pos {
            sep1Pos = sep2Pos + 500
            defaults.set(sep1Pos, forKey: sep1PositionKey)
        }
        if sep1Pos >= sep0Pos {
            sep0Pos = sep1Pos + 600
            defaults.set(sep0Pos, forKey: sep0PositionKey)
        }
        defaults.synchronize()
    }

    private func liveDistanceFromRightEdge(_ item: NSStatusItem) -> CGFloat? {
        guard let window = item.button?.window, let screen = window.screen else { return nil }
        return screen.frame.maxX - window.frame.maxX
    }

    private var layoutIsSafeToCollapse: Bool {
        guard let togglePos = liveDistanceFromRightEdge(toggleItem) else { return true }
        for sep in separatorItems {
            guard let sepPos = liveDistanceFromRightEdge(sep) else { continue }
            if togglePos >= sepPos { return false }
        }
        return true
    }

    private func healLayout() {
        UserDefaults.standard.set(20, forKey: togglePositionKey)
        toggleItem.isVisible = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
            toggleItem.isVisible = true
            configureToggleButton()
            updateDotColor()
        }
    }

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

    // MARK: - Cover panel (pre-macOS 26 fallback overlay)

    private func menuBarBackgroundColor() -> NSColor {
        let sampleX: CGFloat = 400
        let sampleY: CGFloat = 10
        guard let img = CGDisplayCreateImage(CGMainDisplayID(),
                                             rect: CGRect(x: sampleX, y: sampleY, width: 2, height: 2)),
              let data = img.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else {
            return NSColor(white: 0.12, alpha: 1.0)
        }
        let r = CGFloat(ptr[0]) / 255
        let g = CGFloat(ptr[1]) / 255
        let b = CGFloat(ptr[2]) / 255
        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    private func frontAppMenuBarRightEdge() -> CGFloat {
        if AXIsProcessTrusted(), let edge = axFrontAppMenuBarRightEdge(), edge > 100 {
            return edge
        }
        return 700
    }

    private func axFrontAppMenuBarRightEdge() -> CGFloat? {
        let system = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let appEl = appRef else { return nil }
        var mbRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl as! AXUIElement, kAXMenuBarAttribute as CFString, &mbRef) == .success,
              let mbEl = mbRef else { return nil }
        var childRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(mbEl as! AXUIElement, kAXChildrenAttribute as CFString, &childRef) == .success,
              let items = childRef as? [AXUIElement] else { return nil }
        var maxX: CGFloat = 0
        for item in items {
            var posRef: CFTypeRef?
            var szRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &posRef) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &szRef) == .success,
                  let posRaw = posRef, let szRaw = szRef else { continue }
            let pv = posRaw as! AXValue
            let sv = szRaw as! AXValue
            var pos = CGPoint.zero
            var sz = CGSize.zero
            AXValueGetValue(pv, .cgPoint, &pos)
            AXValueGetValue(sv, .cgSize, &sz)
            maxX = max(maxX, pos.x + sz.width)
        }
        return maxX > 100 ? maxX : nil
    }

    private func captureMenuBarBackground(x: CGFloat, width: CGFloat, menuBarHeight: CGFloat) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let sampleH: CGFloat = 80
        let rect = CGRect(
            x: x * scale,
            y: menuBarHeight * scale,
            width: max(width * scale, 1),
            height: sampleH * scale
        )
        guard let cgImage = CGDisplayCreateImage(CGMainDisplayID(), rect: rect) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else { return nil }
        blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
        blurFilter.setValue(20.0, forKey: kCIInputRadiusKey)
        guard let blurred = blurFilter.outputImage else { return nil }
        let cropped = blurred.cropped(to: ciImage.extent)
        let ciCtx = CIContext(options: nil)
        guard let cgBlurred = ciCtx.createCGImage(cropped, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: cgBlurred, size: NSSize(width: max(width, 1), height: menuBarHeight))
    }

    private func showCoverPanel() {
        guard let toggleWindow = toggleItem.button?.window else { return }
        let leftEdge = frontAppMenuBarRightEdge() + 10
        let rightEdge = toggleWindow.frame.minX
        guard rightEdge > leftEdge + 20 else { return }

        let frame = CGRect(
            x: leftEdge,
            y: toggleWindow.frame.origin.y,
            width: rightEdge - leftEdge,
            height: toggleWindow.frame.height
        )

        if coverPanel == nil {
            let panel = NSPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
            panel.ignoresMouseEvents = true
            panel.hasShadow = false
            panel.isOpaque = true
            let iv = NSImageView(frame: NSRect(origin: .zero, size: frame.size))
            iv.autoresizingMask = [.width, .height]
            iv.imageScaling = .scaleAxesIndependently
            panel.contentView = iv
            coverPanel = panel
        }

        let bg = captureMenuBarBackground(x: leftEdge, width: frame.width, menuBarHeight: frame.height)
        (coverPanel?.contentView as? NSImageView)?.image = bg
        coverPanel?.setFrame(frame, display: false)
        coverPanel?.orderFrontRegardless()
    }

    private func hideCoverPanel() { coverPanel?.orderOut(nil) }

    // MARK: - Collapse / expand

    private func collapseMenuBar(step: Int = 1) {
        guard layoutIsSafeToCollapse else {
            healLayout()
            return
        }
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        if major >= 26 {
            collapseViaAssessmentMode(step: step)
        } else {
            currentStep = step
            collapseViaLengthPush()
        }
        updateDotColor()
    }

    private func collapseViaAssessmentMode(step: Int) {
        let prevStep = currentStep
        currentStep = step
        updateSeparatorVisibility()
        updateDotColor()
        updateContextMenuTitle()

        let ownID = Bundle.main.bundleIdentifier ?? "com.menubarbuddy.app"
        var allowed: [String] = [ownID]

        // Use PHYSICAL order: at step k the kth separator from the left is the boundary.
        // Everything to its right stays visible; everything to its left gets hidden.
        if step < separatorItems.count {
            let ordered = physicallyOrderedSeparators()
            allowed += appsRightOfSeparatorItem(ordered[step].item)
        }
        // step >= count → nuclear: only ownID allowed

        // Clock and CC are hidden by omitting their bundle IDs (allowedSystemItems stays empty = unrestricted).
        if hideSystemClock  { allowed.removeAll { $0 == AppDelegate.clockBundleID } }
        if hideControlCenter { allowed.removeAll { $0 == AppDelegate.ccBundleID } }

        barHider.activate(withAllowedBundleIDs: allowed, allowedSystemItems: []) { [self] success, _ in
            if !success {
                currentStep = prevStep
                updateSeparatorVisibility()
                updateDotColor()
                updateContextMenuTitle()
                collapseViaLengthPush()
            }
        }
    }

    private func mbbLog(_ msg: String) {
        let line = msg + "\n"
        if let data = line.data(using: .utf8) {
            let url = URL(fileURLWithPath: "/tmp/mbb-debug.log")
            if let fh = try? FileHandle(forWritingTo: url) {
                fh.seekToEndOfFile(); fh.write(data); try? fh.close()
            } else {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    // Bundle IDs of apps whose menu bar extra sits to the RIGHT of the given separator.
    // Uses the Accessibility API (kAXExtrasMenuBarAttribute) which works on macOS 26
    // without Screen Recording. Falls back to allowing all apps if AX isn't trusted yet.
    private func appsRightOfSeparatorItem(_ sep: NSStatusItem) -> [String] {
        guard let sepWindow = sep.button?.window else {
            mbbLog("MBB appsRight: sep has no window")
            return []
        }
        // AppKit x coordinate (from left edge, logical points)
        let sepX = sepWindow.frame.minX
        mbbLog("MBB appsRight: sep.frame=\(NSStringFromRect(sepWindow.frame)) sepX=\(sepX)")

        // If Accessibility isn't trusted, request it and fall back to all-apps (no-op)
        guard AXIsProcessTrusted() else {
            mbbLog("MBB appsRight: AX not trusted — requesting permission")
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
            // Fall through: return all running apps so Assessment Mode doesn't hide anything
            return allMenuBarBundleIDs()
        }

        let ownID = Bundle.main.bundleIdentifier ?? ""
        var result: [String] = []
        var seen = Set<String>()

        for app in NSWorkspace.shared.runningApplications {
            guard let bid = app.bundleIdentifier, bid != ownID, !seen.contains(bid) else { continue }
            // Only check apps that could have menu bar extras
            guard app.activationPolicy == .accessory || app.activationPolicy == .regular else { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var extrasValue: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &extrasValue)
            guard err == .success, let extrasEl = extrasValue else { continue }

            // Get children (the actual status bar items for this app)
            var childrenValue: CFTypeRef?
            AXUIElementCopyAttributeValue(extrasEl as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue)
            let children = (childrenValue as? [AXUIElement]) ?? []

            // Find the leftmost item this app owns
            var appMinX: CGFloat = CGFloat.greatestFiniteMagnitude
            let items = children.isEmpty ? [extrasEl as! AXUIElement] : children
            for item in items {
                var posValue: CFTypeRef?
                guard AXUIElementCopyAttributeValue(item as AXUIElement, kAXPositionAttribute as CFString, &posValue) == .success,
                      let pv = posValue else { continue }
                var pt = CGPoint.zero
                // AX uses CG coordinates (top-left origin); X is the same as AppKit X
                AXValueGetValue(pv as! AXValue, AXValueType.cgPoint, &pt)
                if pt.x < appMinX { appMinX = pt.x }
            }
            if appMinX == CGFloat.greatestFiniteMagnitude { continue }

            mbbLog("MBB appsRight: bid=\(bid) appMinX=\(appMinX) vs sepX=\(sepX) → \(appMinX >= sepX ? "ALLOW" : "skip")")
            if appMinX >= sepX { seen.insert(bid); result.append(bid) }
        }

        mbbLog("MBB appsRight: returning \(result.count) apps: \(result.joined(separator: ","))")
        return result
    }

    // All bundle IDs for running apps that could have menu bar extras
    private func allMenuBarBundleIDs() -> [String] {
        let ownID = Bundle.main.bundleIdentifier ?? ""
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bid = app.bundleIdentifier, bid != ownID else { return nil }
            guard app.activationPolicy == .accessory || app.activationPolicy == .regular else { return nil }
            return bid
        }
    }

    private func collapseViaLengthPush() {
        guard let sep = separatorItems.first else { return }
        if let button = sep.button {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            button.image = nil
            button.cell?.isEnabled = false
            button.isHighlighted = false
        }
        showCoverPanel()
        let startLen: CGFloat = expandedLength
        let endLen = collapseLength
        let totalSteps = 8
        var animStep = 0
        collapseStepTimer?.invalidate()
        collapseStepTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [self] _ in
            animStep += 1
            let t = CGFloat(animStep) / CGFloat(totalSteps)
            let len = startLen + (endLen - startLen) * t
            safelySetLength(len, on: sep)
            if animStep >= totalSteps {
                collapseStepTimer?.invalidate()
                collapseStepTimer = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                    if isCollapsed, let window = sep.button?.window, window.frame.width < 100 {
                        NSLog("MenuBarBuddy: collapse did not take effect; reverting")
                        expandMenuBar()
                    }
                }
            }
        }
    }

    private func expandMenuBar() {
        collapseStepTimer?.invalidate()
        collapseStepTimer = nil
        if currentStep > 0 {
            barHider.deactivate()
            currentStep = 0
        } else {
            hideCoverPanel()
        }
        // Restore leftmost separator's length (used for length-push fallback)
        if let sep = separatorItems.first {
            safelySetLength(expandedLength, on: sep)
            sep.button?.cell?.isEnabled = true
        }
        updateSeparatorVisibility()
        updateDotColor()
        updateContextMenuTitle()
    }

    // MARK: - Hosting watchdog + self-repair

    private func windowIsParkedOffscreen(_ window: NSWindow) -> Bool {
        let frame = window.frame
        if window.screen != nil { return false }
        return !NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    private func itemsLookOrphaned() -> Bool {
        guard let toggleWindow = toggleItem.button?.window else {
            NSLog("MenuBarBuddy: watchdog: toggle has no window")
            return true
        }
        if windowIsParkedOffscreen(toggleWindow) {
            NSLog("MenuBarBuddy: watchdog: toggle parked at \(toggleWindow.frame)")
            return true
        }
        guard !isCollapsed else { return false }
        for (i, item) in separatorItems.enumerated() {
            guard item.isVisible, let sepWindow = item.button?.window else {
                if item.isVisible {
                    NSLog("MenuBarBuddy: watchdog: separator \(i) has no window")
                    return true
                }
                continue
            }
            if windowIsParkedOffscreen(sepWindow) {
                NSLog("MenuBarBuddy: watchdog: separator \(i) parked at \(sepWindow.frame)")
                return true
            }
            if toggleWindow.frame.intersects(sepWindow.frame) {
                NSLog("MenuBarBuddy: watchdog: items overlap (toggle \(toggleWindow.frame), sep \(i) \(sepWindow.frame))")
                return true
            }
        }
        return false
    }

    private func checkHosting() {
        guard !screensAsleep, !sessionLocked, Date() >= watchdogGraceUntil,
              NSEvent.pressedMouseButtons == 0 else {
            parkedStreak = 0
            return
        }
        guard itemsLookOrphaned() else {
            parkedStreak = 0
            return
        }
        parkedStreak += 1
        guard parkedStreak >= 3 else { return }
        parkedStreak = 0
        if Date().timeIntervalSince(lastHostingRecoveryAt) > 24 * 3600 {
            hostingRecoveryAttempts = 0
        }
        lastHostingRecoveryAt = Date()
        if hostingRecoveryAttempts < 2 {
            hostingRecoveryAttempts += 1
            recreateStatusItems()
        } else if !repairAlertShown {
            repairAlertShown = true
            showRepairAlert()
        }
    }

    private func showRepairAlert() {
        let lastAlertKey = "MenuBarBuddy.lastRepairAlertAt"
        let last = UserDefaults.standard.double(forKey: lastAlertKey)
        if last > 0, Date().timeIntervalSince1970 - last < 20 * 3600 {
            NSLog("MenuBarBuddy: watchdog: suppressing repair alert (shown recently)")
            return
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: lastAlertKey)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "MenuBarBuddy's icons are being blocked"
        alert.informativeText = "macOS blocked this copy of the app after an unclean shutdown. Repair re-registers the app under a fresh identity and relaunches it. Your settings and icon positions are kept."
        alert.addButton(withTitle: "Repair and Relaunch")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)
        if response == .alertFirstButtonReturn {
            performSelfRepair()
        }
    }

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
            onStartEmojiChange: { _ in
                // Separators now use colored line images, not emoji
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
        if isCollapsed { expandMenuBar() }
        mouseTimer?.invalidate()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isCollapsed { expandMenuBar() }
        return .terminateNow
    }
}
