import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    var onEmojiChange: ((String) -> Void)?
    var onStartEmojiChange: ((String) -> Void)?
    var onPushMultiplierChange: (() -> Void)?

    @State private var endInput: String = ""
    @State private var startInput: String = ""
    @FocusState private var focusedField: Field?

    enum Field { case end, start }

    var body: some View {
        VStack(spacing: 16) {
            Text("MenuBarBuddy")
                .font(.title.bold())

            // Toggle icon (📁)
            GroupBox("Folder Icon (toggle)") {
                HStack(spacing: 16) {
                    Text(store.selectedEmoji)
                        .font(.system(size: 48))
                        .frame(width: 64, height: 56)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("", text: $endInput)
                                .focused($focusedField, equals: .end)
                                .font(.system(size: 20))
                                .frame(width: 50, height: 28)
                                .textFieldStyle(.roundedBorder)

                            Button("Pick") {
                                focusedField = .end
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    NSApp.orderFrontCharacterPalette(nil)
                                }
                            }
                        }
                        Text("Click to collapse/expand")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Start marker (≡)
            GroupBox("Start Marker (boundary)") {
                HStack(spacing: 16) {
                    Text(store.startEmoji)
                        .font(.system(size: 48))
                        .frame(width: 64, height: 56)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("", text: $startInput)
                                .focused($focusedField, equals: .start)
                                .font(.system(size: 20))
                                .frame(width: 50, height: 28)
                                .textFieldStyle(.roundedBorder)

                            Button("Pick") {
                                focusedField = .start
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    NSApp.orderFrontCharacterPalette(nil)
                                }
                            }
                        }
                        Text("Cmd-drag right of items to hide")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()

            Text("Quick Picks")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(quickPicks, id: \.self) { emoji in
                        Button(action: {
                            if focusedField == .start {
                                selectStart(emoji)
                            } else {
                                selectEnd(emoji)
                            }
                        }) {
                            Text(emoji)
                                .font(.system(size: 24))
                                .frame(width: 36, height: 36)
                                .background(
                                    (store.selectedEmoji == emoji || store.startEmoji == emoji)
                                    ? Color.accentColor.opacity(0.3) : Color.clear
                                )
                                .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 140)

            Divider()

            HStack {
                Button("Still seeing items? Push harder") {
                    store.pushMultiplier *= 2
                    onPushMultiplierChange?()
                }
                .font(.caption)

                if store.pushMultiplier > 1 {
                    Button("Reset") {
                        store.pushMultiplier = 1
                        onPushMultiplierChange?()
                    }
                    .font(.caption)
                }
            }

            LabeledContent("Hotkey", value: "Ctrl + Opt + Space")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(20)
        .frame(width: 350, height: 540)
        .onAppear {
            endInput = store.selectedEmoji
            startInput = store.startEmoji
        }
        .onChange(of: endInput) { _, newValue in
            guard let last = newValue.last else { return }
            let emoji = String(last)
            if emoji != store.selectedEmoji { selectEnd(emoji) }
            if endInput != emoji { endInput = emoji }
        }
        .onChange(of: startInput) { _, newValue in
            guard let last = newValue.last else { return }
            let emoji = String(last)
            if emoji != store.startEmoji { selectStart(emoji) }
            if startInput != emoji { startInput = emoji }
        }
    }

    private func selectEnd(_ emoji: String) {
        store.selectedEmoji = emoji
        onEmojiChange?(emoji)
        endInput = emoji
    }

    private func selectStart(_ emoji: String) {
        store.startEmoji = emoji
        onStartEmojiChange?(emoji)
        startInput = emoji
    }

    private let quickPicks = [
        "📁", "📂", "🗂", "📋", "📌", "⚙️", "🔧", "💻",
        "🔔", "⚡", "💡", "🔥", "⭐", "✨", "💎", "🎯",
        "◀️", "▶️", "⏩", "⏪", "⬆️", "⬇️", "⬅️", "➡️",
        "◼️", "◻️", "▪️", "▫️", "🔲", "🔳", "⚫", "⚪",
        "🔴", "🟠", "🟡", "🟢", "🔵", "🟣", "🟤", "⭕",
        "☰", "☱", "☲", "☳", "☴", "☵", "☶", "☷",
        "✦", "✧", "◆", "◇", "○", "●", "□", "■",
        "△", "▽", "▷", "◁", "♠", "♣", "♥", "♦",
        "🚀", "🌍", "🏠", "☀️", "🌙", "❄️", "🐱", "🐶",
    ]
}
