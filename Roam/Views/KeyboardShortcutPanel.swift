import Foundation
import SwiftUI
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "KeyboardShortcut")

extension View {
    func customKeyboardShortcut(_ title: CustomKeyboardShortcut.Key) -> some View {
        modifier(CustomKeyboardShortcutModifier(title: title))
    }
}

struct CustomKeyboardShortcutModifier: ViewModifier {
    @KeyboardShortcutStorage var shortcut: CustomKeyboardShortcut?

    init(title: CustomKeyboardShortcut.Key, defaultShortcut: CustomKeyboardShortcut? = nil) {
        self._shortcut = KeyboardShortcutStorage(title)
    }

    func body(content: Content) -> some View {
        if let key = shortcut?.key, let modifiers = shortcut?.modifiers {
            return AnyView(content.keyboardShortcut(key, modifiers: modifiers))
        } else {
            return AnyView(content)
        }
    }
}

@propertyWrapper
struct KeyboardShortcutStorage: DynamicProperty {
    private let title: CustomKeyboardShortcut.Key
    @AppStorage var data: Data?

    var wrappedValue: CustomKeyboardShortcut? {
        get {
            if let data = data {
                if let sc = try? PropertyListDecoder().decode(CustomKeyboardShortcut.self, from: data) {
                    return sc
                }
            }
            if let sc = CustomKeyboardShortcut.defaults[title] {
                return CustomKeyboardShortcut(title: title, shortcut: sc)
            }
            return nil
        }
        nonmutating set {
            if let newValue = newValue {
                data = try? PropertyListEncoder().encode(newValue)
            } else {
                data = nil
            }
        }
    }

    var projectedValue: Binding<CustomKeyboardShortcut?> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }

    init(_ title: CustomKeyboardShortcut.Key) {
        self.title = title
        self._data = AppStorage("keyboard-shortcut-\(title)")
    }
}

struct CustomKeyboardShortcut: Identifiable, Codable {
    let title: CustomKeyboardShortcut.Key
    let key: KeyEquivalent?
    let modifiers: EventModifiers
    var id: String {
        title.rawValue
    }
    
    init(title: CustomKeyboardShortcut.Key, key: KeyEquivalent, modifiers: EventModifiers) {
        self.title = title
        self.key = key
        self.modifiers = modifiers
    }
    
    init(title: CustomKeyboardShortcut.Key, shortcut: KeyboardShortcut) {
        self.title = title
        self.key = shortcut.key
        self.modifiers = shortcut.modifiers
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(CustomKeyboardShortcut.Key.self, forKey: .title)
        key = try container.decode(KeyEquivalent.self, forKey: .key)
        let modifiersRawValue = try container.decode(Int.self, forKey: .modifiers)
        modifiers = EventModifiers(rawValue: modifiersRawValue)
    }


    var keys: String {
        var keyBuilder: String = ""
        if key == nil {
            return ""
        }
        for pair in [(EventModifiers.command, "⌘"), (EventModifiers.shift, "⇧"), (EventModifiers.control, "^"), (EventModifiers.option, "⌥")] {
            if modifiers.contains(pair.0) {
                keyBuilder.append(pair.1)
                keyBuilder.append(" ")
            }
        }
        if let key {
            print("Getting new repr \(key.printableRepresentation) and \(key.character) and \(key.character.utf8)")
            keyBuilder.append(key.printableRepresentation)
        }
        return keyBuilder
    }

    static var defaults: [Key: KeyboardShortcut] = [
        .back: KeyboardShortcut(.leftArrow, modifiers: .command),
        .power: KeyboardShortcut(.return, modifiers: .command),
        .home: KeyboardShortcut(KeyEquivalent("h"), modifiers: .command),
        .volumeDown: KeyboardShortcut(.downArrow, modifiers: .command),
        .volumeUp: KeyboardShortcut(.upArrow, modifiers: .command),
        .mute: KeyboardShortcut(KeyEquivalent("m"), modifiers: .command),
        .playPause: KeyboardShortcut(KeyEquivalent("p"), modifiers: .command),
        .ok: KeyboardShortcut(.return, modifiers: .shift),
        .left: KeyboardShortcut(.leftArrow, modifiers: []),
        .right: KeyboardShortcut(.rightArrow, modifiers: []),
        .up: KeyboardShortcut(.upArrow, modifiers: []),
        .down: KeyboardShortcut(.downArrow, modifiers: []),
        .keyboardShortcuts: KeyboardShortcut(KeyEquivalent("k"), modifiers: .command),
        .chatWithDeveloper: KeyboardShortcut(KeyEquivalent("j"), modifiers: .command)
    ]
    
    enum CodingKeys: String, CodingKey {
        case title
        case key
        case modifiers
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(key, forKey: .key)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
    
    func persist() {
        logger.info("Saving shortcut with title \(self.title.rawValue) key \(keys)")
        do {
            let data = try PropertyListEncoder().encode(self)
            UserDefaults.standard.set(data, forKey: "keyboard-shortcut-\(title)")
        } catch {
            logger.error("Error encoding keyboard shortcut to string \(error)")
        }
    }
    
    func reset() {
        UserDefaults.standard.removeObject(forKey: "keyboard-shortcut-\(title)")
    }
    
    init(title: Key) {
        if let data = UserDefaults.standard.data(forKey: "keyboard-shortcut-\(title)"),
           let shortcut = try? PropertyListDecoder().decode(Self.self, from: data) {
            self = shortcut
        } else if let defaultShortcut = Self.defaults[title] {
            self = Self(title: title, shortcut: defaultShortcut)
        } else {
            self.title = title
            self.key = nil
            self.modifiers = .command
        }
    }

    public enum Key: String, CaseIterable, Codable {
        case back = "Back"
        case power = "Power"
        case home = "Home"
        case volumeDown = "Volume Down"
        case volumeUp = "Volume Up"
        case mute = "Mute"
        case playPause = "Play/Pause"
        case ok = "Ok"
        case left = "Left"
        case right = "Right"
        case up = "Up"
        case down = "Down"
        case keyboardShortcuts = "Keyboard Shortcuts"
        case chatWithDeveloper = "Chat with Developer"
        case options = "Options"
        case headphonesMode = "Headphones Mode"
        case instantReplay = "Instant Replay"
        case fastForward = "Fast Forward"
        case rewind = "Rewind"
    }
}

extension KeyEquivalent: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let character = value.first else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid key equivalent")
        }
        self = KeyEquivalent(character)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(self.character))
    }
}

extension EventModifiers {
    var isEmpty: Bool {
        return !self.contains(.shift) && !self.contains(.command) && !self.contains(.control) && !self.contains(.option)
    }
}

extension KeyEquivalent {
    var isPrintableCharacter: Bool {
        let unprintableCharacters: Set<KeyEquivalent> = [
            .delete, .escape, .return,
            .leftArrow, .rightArrow, .upArrow, .downArrow,
            .home, .end, .pageUp, .pageDown
        ]
        
        return !unprintableCharacters.contains(self)
    }
    var printableRepresentation: String {
        switch self {
        case " ":
            return "Space"
        case .return:
            return "⏎"
        case .tab:
            return "⇥"
        case .space:
            return "Space"
        case .delete:
            return "⌫"
        case .escape:
            return "⎋"
        case .leftArrow:
            return "←"
        case .rightArrow:
            return "→"
        case .upArrow:
            return "↑"
        case .downArrow:
            return "↓"
        case .home:
            return "↖"
        case .end:
            return "↘"
        case .pageUp:
            return "⇞"
        case .pageDown:
            return "⇟"
        default:
            return String(self.character).uppercased()
        }
    }
}

extension EventModifiers: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(Int.self)
        self = EventModifiers(rawValue: rawValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

struct ShortcutDisplay: View {
    @KeyboardShortcutStorage var shortcut: CustomKeyboardShortcut?
    let title: CustomKeyboardShortcut.Key

    
    init(_ title: CustomKeyboardShortcut.Key) {
        self.title = title
        self._shortcut = KeyboardShortcutStorage(title)
    }
    
    @ViewBuilder
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(title.rawValue)
                Spacer()
                Text(shortcut?.keys ?? "")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
            
#if os(macOS)
            if shortcut?.key?.isPrintableCharacter == true && shortcut?.modifiers.contains(.command) == false {
                Text("Letters, numbers, and punctuation often don't work as keyboard shortcuts without a command modifier (⌘)")
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.6))
            }
#endif
        }
    }
}

struct KeyboardShortcutPanel: View {
    var shortcuts: [CustomKeyboardShortcut] {
        return CustomKeyboardShortcut.Key.allCases.map{
            CustomKeyboardShortcut(title: $0)
        }
    }
    
    @FocusState private var focusedShortcut: CustomKeyboardShortcut.Key?

    @ViewBuilder
    var body: some View {
        Form {
            #if os(macOS)
            Text("Select a row below to change the shortcut, or right click it to reset the shortcut back to its original state")
                .foregroundStyle(.secondary)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive, action: {
                        for shortcut in shortcuts {
                            shortcut.reset()
                        }
                    }, label: {
                        Label("Reset All", systemImage: "arrow.uturn.backward")
                    })
                }
                .contextMenu {
                    Button(role: .destructive, action: {
                        for shortcut in shortcuts {
                            shortcut.reset()
                        }
                    }, label: {
                        Label("Reset All", systemImage: "arrow.uturn.backward")
                    })
                }
            #else
            Text("Select a row below to change the shortcut, or swipe to reset")
                .foregroundStyle(.secondary)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive, action: {
                        for shortcut in shortcuts {
                            shortcut.reset()
                        }
                    }, label: {
                        Label("Reset All", systemImage: "arrow.uturn.backward")
                    })
                }
                .contextMenu {
                    Button(role: .destructive, action: {
                        for shortcut in shortcuts {
                            shortcut.reset()
                        }
                    }, label: {
                        Label("Reset All", systemImage: "arrow.uturn.backward")
                    })
                }

            #endif
            ForEach(shortcuts) { shortcut in
                ShortcutDisplay(shortcut.title)
                .padding(3)
                .contentShape(RoundedRectangle(cornerRadius: 8.0))
                .focusable()
                .focused($focusedShortcut, equals: shortcut.title)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.secondary, lineWidth: 4)
                        .opacity(focusedShortcut == shortcut.title ? 1 : 0)
                        .scaleEffect(focusedShortcut == shortcut.title ? 1 : 1.1)
                        .animation(focusedShortcut == shortcut.title ? .easeIn(duration: 0.2) : .easeOut(duration: 0.0), value: focusedShortcut == shortcut.title)
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive, action: {
                        shortcut.reset()
                    }, label: {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                    })
                }
                .contextMenu {
                    Button(role: .destructive, action: {
                        shortcut.reset()
                    }, label: {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                    })
                }
            }
        }
        .onKeyDown({ key in
            if let focusedShortcut {
                CustomKeyboardShortcut(title: focusedShortcut, shortcut: KeyboardShortcut(key.key, modifiers: key.modifiers)).persist()
            }
        }, captureShortcuts: true)
        .formStyle(.grouped)
        .navigationTitle("Keyboard Shortcuts")
                .frame(maxWidth: 500)
    }
}

#Preview {
    KeyboardShortcutPanel()
}
