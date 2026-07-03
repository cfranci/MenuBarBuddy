import Foundation

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var selectedEmoji: String {
        didSet { defaults.set(selectedEmoji, forKey: emojiKey) }
    }

    @Published var startEmoji: String {
        didSet { defaults.set(startEmoji, forKey: startEmojiKey) }
    }

    @Published var pushMultiplier: Double {
        didSet { defaults.set(pushMultiplier, forKey: pushMultiplierKey) }
    }

    private let defaults = UserDefaults.standard
    private let emojiKey = "MenuBarBuddy.selectedEmoji"
    private let startEmojiKey = "MenuBarBuddy.startEmoji"
    private let pushMultiplierKey = "MenuBarBuddy.pushMultiplier"

    init() {
        Self.migrateFromOldBundleID(into: defaults)
        self.selectedEmoji = defaults.string(forKey: emojiKey) ?? "📁"
        self.startEmoji = defaults.string(forKey: startEmojiKey) ?? "☰"
        self.pushMultiplier = defaults.double(forKey: pushMultiplierKey)
        if self.pushMultiplier < 1 { self.pushMultiplier = 1 }
    }

    // macOS 26's menu bar host blacklists a bundle ID whenever its process
    // dies violently while a status item is being manipulated, orphaning all
    // of its items on every launch after that. The escape is a new bundle ID
    // (v2 -> app -> v3 -> v4 -> ...; the app can bump itself, see
    // AppDelegate.performSelfRepair), so derive the list of previous domains
    // from the current ID and copy the user's settings forward.
    static var previousBundleIDs: [String] {
        var domains: [String] = []
        if let id = Bundle.main.bundleIdentifier,
           let range = id.range(of: #"\.v(\d+)$"#, options: .regularExpression),
           let n = Int(id[range].dropFirst(2)), n > 3 {
            domains = stride(from: n - 1, through: 3, by: -1).map { "com.menubarbuddy.v\($0)" }
        }
        domains.append("com.menubarbuddy.app")
        return domains
    }

    static func nextBundleID(after id: String) -> String {
        if let range = id.range(of: #"\.v(\d+)$"#, options: .regularExpression),
           let n = Int(id[range].dropFirst(2)) {
            return String(id[..<range.lowerBound]) + ".v\(n + 1)"
        }
        return id + ".v5"
    }

    private static func migrateFromOldBundleID(into defaults: UserDefaults) {
        let migratedKey = "MenuBarBuddy.migratedSettings"
        guard !defaults.bool(forKey: migratedKey) else { return }
        for key in ["MenuBarBuddy.selectedEmoji", "MenuBarBuddy.startEmoji",
                    "MenuBarBuddy.pushMultiplier", "MenuBarBuddy.startAtLogin"] {
            guard defaults.object(forKey: key) == nil else { continue }
            for domain in previousBundleIDs {
                if let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString) {
                    defaults.set(value, forKey: key)
                    break
                }
            }
        }
        defaults.set(true, forKey: migratedKey)
    }
}
