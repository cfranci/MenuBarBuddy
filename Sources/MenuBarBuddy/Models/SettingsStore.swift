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
        self.selectedEmoji = defaults.string(forKey: emojiKey) ?? "📁"
        self.startEmoji = defaults.string(forKey: startEmojiKey) ?? "☰"
        self.pushMultiplier = defaults.double(forKey: pushMultiplierKey)
        if self.pushMultiplier < 1 { self.pushMultiplier = 1 }
    }
}
