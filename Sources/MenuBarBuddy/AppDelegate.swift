import AppKit
import SwiftUI
import HotKey
import ServiceManagement
import ExceptionShield

/// Color families for the toggle dot. Every non-classic style renders through
/// the animated two-tone engine; classic keeps the original green/gray fade.
enum DotStyle: String, CaseIterable {
    case classic, rainbow, ocean, lava, aurora, custom

    var title: String {
        switch self {
        case .classic: return "Classic Green"
        case .rainbow: return "Rainbow"
        case .ocean:   return "Ocean"
        case .lava:    return "Lava"
        case .aurora:  return "Aurora"
        case .custom:  return "Custom Color…"
        }
    }

    /// (baseHue, drift range, top/bottom hue offset). Rainbow ignores these
    /// and cycles the full wheel; custom substitutes the user's hue.
    var palette: (base: CGFloat, drift: CGFloat, offset: CGFloat) {
        switch self {
        case .ocean:  return (0.55, 0.07, 0.06)
        case .lava:   return (0.02, 0.05, 0.06)
        case .aurora: return (0.38, 0.08, 0.34)
        default:      return (0.45, 0.00, 0.33)
        }
    }
}

/// How the two tones move inside the dot.
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
    private var appearanceMenu: NSMenu?
    private var rainbowTimer: Timer?
    private var rainbowHue: CGFloat = 0.45  // start near the classic mint
    private var rainbowWavePhase: CGFloat = 0
    private var palettePhase: CGFloat = 0   // slow drift for themed palettes
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
    // Display sleep, screen lock, and display reconfiguration all move or
    // detach status item windows transiently; the watchdog must stand down
    // through them or every overnight idle looks like an orphaning.
    private var watchdogGraceUntil = Date.distantPast
    private var screensAsleep = false
    private var sessionLocked = false
    private var lastHostingRecoveryAt = Date.distantPast

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
        // Displays connecting/disconnecting/mirroring (external monitors, TVs,
        // Sidecar, virtual displays) shuffle status item windows for several
        // seconds. Never count those frames as orphaning.
        deferWatchdog(seconds: 60)
    }

    /// Suspend the hosting watchdog while the machine is in a state where
    /// status item geometry is meaningless, and give it a grace period after
    /// coming back. Without this, an overnight display sleep or a lock screen
    /// reliably racked up 3 "orphaned" ticks and ended in a bogus repair alert
    /// (the bundle ID climbed v6 -> v10 in one week that way).
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

    @objc private func screensDidSleep() {
        screensAsleep = true
        parkedStreak = 0
    }

    @objc private func screensDidWake() {
        screensAsleep = false
        deferWatchdog(seconds: 60)
    }

    @objc private func sessionLockedNotification() {
        sessionLocked = true
        parkedStreak = 0
    }

    @objc private func sessionUnlockedNotification() {
        sessionLocked = false
        deferWatchdog(seconds: 30)
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

    /// Two-tone animated dot: one hue on top, another below, blended along a
    /// moving boundary. Motions layer: each active motion contributes a blend
    /// component and they are averaged per-pixel, so wave + spin + ripple all
    /// show at once; breathe modulates the radius independently. Rendered
    /// per-pixel into a small retina bitmap (36x36 px, trivial at 20fps).
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
        var dotRadius = 4.5 * scale               // same 9pt dot as the classic image
        if motions.contains(.breathe) {
            // The whole dot swells and shrinks; layers under any boundary motion.
            dotRadius *= 0.88 + 0.12 * sin(wavePhase)
        }
        let center = CGFloat(px) / 2
        let amplitude = dotRadius * 0.35          // wave height
        let blendBand = dotRadius * 0.9           // soft gradient thickness
        let bytesPerRow = rep.bytesPerRow
        let (tr, tg, tb) = (top.redComponent, top.greenComponent, top.blueComponent)
        let (br, bg, bb) = (bottom.redComponent, bottom.greenComponent, bottom.blueComponent)
        for y in 0..<px {
            for x in 0..<px {
                let dx = CGFloat(x) + 0.5 - center
                let dy = CGFloat(y) + 0.5 - center    // positive = below center (bitmap is top-down)
                let dist = (dx * dx + dy * dy).squareRoot()
                let alpha = max(0, min(1, dotRadius - dist + 0.5))   // 1px antialiased rim
                let offset = y * bytesPerRow + x * 4
                if alpha <= 0 {
                    bytes[offset] = 0; bytes[offset + 1] = 0; bytes[offset + 2] = 0; bytes[offset + 3] = 0
                    continue
                }
                // Blend factor: 0 = top color, 1 = bottom color. Each active
                // motion contributes a component; the average layers them.
                var components: [CGFloat] = []
                if motions.contains(.wave) {
                    // Wavy boundary: crosses the middle, drifting with wavePhase.
                    let wave = amplitude * sin((dx / dotRadius) * .pi * 1.4 + wavePhase)
                    var tw = (dy - wave) / blendBand + 0.5
                    tw = max(0, min(1, tw))
                    components.append(tw * tw * (3 - 2 * tw))        // smoothstep
                }
                if motions.contains(.ripple) {
                    // Concentric rings flowing outward from the center.
                    components.append(0.5 + 0.5 * sin((dist / dotRadius) * .pi * 2.2 - wavePhase * 2))
                }
                if motions.contains(.spin) {
                    // A two-tone gradient rotating around the center.
                    components.append(0.5 + 0.5 * sin(atan2(dy, dx) + wavePhase))
                }
                if motions.contains(.steady) {
                    // Fixed soft horizontal split, no movement.
                    var ts = dy / blendBand + 0.5
                    ts = max(0, min(1, ts))
                    components.append(ts * ts * (3 - 2 * ts))
                }
                // Breathe alone (or nothing) = solid top color.
                let t = components.isEmpty ? 0 : components.reduce(0, +) / CGFloat(components.count)
                let r = tr + (br - tr) * t
                let g = tg + (bg - tg) * t
                let b = tb + (bb - tb) * t
                bytes[offset]     = UInt8(r * alpha * 255)           // premultiplied RGBA
                bytes[offset + 1] = UInt8(g * alpha * 255)
                bytes[offset + 2] = UInt8(b * alpha * 255)
                bytes[offset + 3] = UInt8(alpha * 255)
            }
        }
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        return img
    }

    // MARK: - Appearance (dot style / motion / speed)

    /// Kept for back-compat: older builds persisted a single Rainbow Dot flag.
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
            return rainbowEnabled ? .rainbow : .classic   // pre-appearance builds
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "MenuBarBuddy.dotStyle")
            rainbowEnabled = newValue != .classic         // keep the old flag coherent
        }
    }

    /// Motions LAYER: any combination can be active at once (wave + spin +
    /// breathe, etc.). Persisted as a comma-joined list; a bare single value
    /// from older builds parses the same way. nil = default [wave]; an empty
    /// string is a deliberate "no motion" (solid dot).
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

    /// Hue (0..1) for the Custom style, set from the color panel.
    private var customDotHue: CGFloat {
        get {
            let saved = UserDefaults.standard.double(forKey: "MenuBarBuddy.customDotHue")
            return saved > 0 ? CGFloat(saved) : 0.75      // default: purple
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
        // Full hue cycle roughly every 8 seconds (rainbow only).
        rainbowHue = (rainbowHue + speed * 0.05 / 8.0).truncatingRemainder(dividingBy: 1.0)
        // Themed palettes drift slowly around their base hue instead.
        palettePhase = (palettePhase + speed * 0.05 * 2 * .pi / 10).truncatingRemainder(dividingBy: 2 * .pi)
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
        // Boundary movement: ~one sweep every 4 seconds at normal speed.
        rainbowWavePhase = (rainbowWavePhase + speed * 0.05 * 2 * .pi / 4).truncatingRemainder(dividingBy: 2 * .pi)

        let topHue: CGFloat
        let bottomHue: CGFloat
        switch style {
        case .rainbow, .classic:
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
        if style == .custom {
            openCustomColorPanel()
        }
        dotStyle = style
        refreshAppearanceMenu()
        updateDotColor()
    }

    @objc private func selectDotMotion(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let motion = DotMotion(rawValue: raw) else { return }
        var set = dotMotions
        if set.contains(motion) {
            set.remove(motion)
        } else {
            set.insert(motion)
        }
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

    /// Sync the checkmarks in the Appearance submenu to the persisted settings.
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
            refreshAppearanceMenu()
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

    /// True when the window is parked outside every online display. A plain
    /// `y < 0` test is wrong on multi-display setups: a monitor arranged below
    /// or left of the main screen legitimately puts its menu bar windows at
    /// negative global coordinates (that false positive is what fired the
    /// repair alert daily on a 3-display arrangement).
    private func windowIsParkedOffscreen(_ window: NSWindow) -> Bool {
        let frame = window.frame
        if window.screen != nil { return false }
        return !NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    /// Signature of the macOS 26 orphaning: the app runs, isVisible is true,
    /// but the items' windows are parked outside every display or crammed on
    /// top of each other at a display edge instead of being laid out in the
    /// menu bar.
    private func itemsLookOrphaned() -> Bool {
        // The toggle dot must be sanely hosted in EVERY state (only the
        // separator's geometry is intentionally weird while collapsed). This
        // must not skip collapsed state: an orphaned separator still accepts a
        // 10,000 length, so a blind-while-collapsed watchdog never fires.
        guard let toggleWindow = toggleItem.button?.window else {
            NSLog("MenuBarBuddy: watchdog: toggle has no window")
            return true
        }
        if windowIsParkedOffscreen(toggleWindow) {
            NSLog("MenuBarBuddy: watchdog: toggle parked at \(toggleWindow.frame)")
            return true
        }
        guard !isCollapsed else { return false }
        guard let separatorWindow = separatorItem.button?.window else {
            NSLog("MenuBarBuddy: watchdog: separator has no window")
            return true
        }
        if windowIsParkedOffscreen(separatorWindow) {
            NSLog("MenuBarBuddy: watchdog: separator parked at \(separatorWindow.frame)")
            return true
        }
        if toggleWindow.frame.intersects(separatorWindow.frame) {
            NSLog("MenuBarBuddy: watchdog: items overlap (toggle \(toggleWindow.frame), separator \(separatorWindow.frame))")
            return true
        }
        return false
    }

    /// Escalating recovery: three consecutive positives (~15s) to rule out
    /// transient states, then recreate the items in-process (twice max), then
    /// offer the bundle-ID self-repair once. Stands down entirely while the
    /// screens are asleep, the session is locked, a display reconfiguration
    /// just happened, or a mouse button is down (mid-drag geometry lies).
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
        // Isolated incidents days apart shouldn't accumulate into the alert:
        // a real blacklisting re-orphans within seconds of a recreation.
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
        // The modal alert freezes every timer in the app until dismissed, so a
        // relaunch (login items start daily) must not re-raise it on a stale
        // grudge: at most one alert per 20h, persisted across restarts.
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

    /// Every termination path must expand first — dying while collapsed is
    /// what gets the bundle ID blacklisted. quitApp() and the signal handlers
    /// already do; this catches the rest (AppleScript quit, logout).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isCollapsed {
            expandMenuBar()
        }
        return .terminateNow
    }
}
