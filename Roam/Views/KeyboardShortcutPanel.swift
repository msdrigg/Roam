import Foundation
import SwiftUI

struct KeyboardShortcut: Identifiable {
    let title: String
    let keys: String
    var id: String {
        title
    }
}

struct KeyboardShortcutPanel: View {
    let columns: [GridItem] = Array(repeating: .init(.fixed(200)), count: 3) // Adjust the count as needed for columns
    
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
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(shortcuts) { shortcut in
                HStack {
                    Text(shortcut.title)
                        .font(.headline)
                    Spacer().frame(maxWidth: 10)
                    Text(shortcut.keys)
                        .foregroundColor(.gray)
                        .font(.subheadline)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
    }
}

#Preview {
    KeyboardShortcutPanel()
}
