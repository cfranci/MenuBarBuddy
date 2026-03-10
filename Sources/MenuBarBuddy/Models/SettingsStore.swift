import Foundation

class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var selectedEmoji: String {
        didSet { defaults.set(selectedEmoji, forKey: emojiKey) }
    }

    @Published var startEmoji: String {
        didSet { defaults.set(startEmoji, forKey: startEmojiKey) }
    }

    private let defaults = UserDefaults.standard
    private let emojiKey = "MenuBarBuddy.selectedEmoji"
    private let startEmojiKey = "MenuBarBuddy.startEmoji"

    init() {
        self.selectedEmoji = defaults.string(forKey: emojiKey) ?? "📁"
        self.startEmoji = defaults.string(forKey: startEmojiKey) ?? "☰"
    }
}
