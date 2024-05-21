import Foundation
import SwiftUI

struct KeyboardShortcut: Identifiable {
    let title: String
    let keys: String
    var id: String {
        title
    }
}

let shortcuts: [KeyboardShortcut] = [
    KeyboardShortcut(title: "Back", keys: "⌘◀"),
    KeyboardShortcut(title: "Power", keys: "⌘⏎"),
    KeyboardShortcut(title: "Home", keys: "⌘H"),

    KeyboardShortcut(title: "Volume down", keys: "⌘▼"),
    KeyboardShortcut(title: "Volume up", keys: "⌘▲"),
    KeyboardShortcut(title: "Mute", keys: "⌘M"),

    KeyboardShortcut(title: "Play/Pause", keys: "⌘P"),
    KeyboardShortcut(title: "Ok", keys: "Space"),
    KeyboardShortcut(title: "Left", keys: "◀"),
    KeyboardShortcut(title: "Right", keys: "▶"),
    KeyboardShortcut(title: "Up", keys: "▲"),
    KeyboardShortcut(title: "Down", keys: "▼"),

    KeyboardShortcut(title: "Keyboard Shortcuts", keys: "⌘K"),
]

struct KeyboardShortcutPanel: View {
    var body: some View {
        List {
            ForEach(shortcuts) { shortcut in
                HStack {
                    Text(shortcut.title)
                        .font(.headline)
                    Spacer()
                    Text(shortcut.keys)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }
        }
        .navigationTitle("Keyboard Shortcuts")
    }
}

#Preview {
    KeyboardShortcutPanel()
}
