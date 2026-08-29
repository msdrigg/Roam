#if !os(macOS)
    import Foundation
    import OSLog
    import SwiftUI
    import UIKit

    struct OnKeyPressModifier: ViewModifier {
        let onKeyPress: (KeyboardShortcut) -> Void
        let onKeyboardShortcut: ((CustomKeyboardShortcut.Key) -> Void)?
        let enabled: Bool

        @AllCustomKeyboardShortcuts private var allKeyboardShortcuts: [CustomKeyboardShortcut]

        func body(content: Content) -> some View {
            if enabled {
                // Overlay a sibling first-responder view instead of re-hosting
                // `content` in a nested UIHostingController. Re-hosting detaches the
                // content's scroll view from the enclosing UINavigationController -
                // which breaks large-title collapse and the scroll-edge effect - and
                // makes the nested controller re-apply the window safe area, double-
                // counting the bottom inset (the home-indicator gap / clipping seen in
                // the Keyboard Shortcuts panel). Mirrors the macOS implementation,
                // which overlays a non-hit-testing NSView.
                content.overlay(
                    KeyPressableRepresentable(
                        onKeyPress: onKeyPress,
                        onKeyboardShortcut: onKeyboardShortcut,
                        keyboardShortcuts: onKeyboardShortcut != nil ? allKeyboardShortcuts : nil
                    )
                    .allowsHitTesting(false)
                )
            } else {
                content
            }
        }
    }

    extension View {
        func onKeyDown(_ onKeyPress: @escaping (KeyboardShortcut) -> Void, onKeyboardShortcut: ((CustomKeyboardShortcut.Key) -> Void)? = nil, enabled: Bool = true) -> some View {
            modifier(OnKeyPressModifier(onKeyPress: onKeyPress, onKeyboardShortcut: onKeyboardShortcut, enabled: enabled))
        }
    }

    private struct KeyPressableRepresentable: UIViewRepresentable {
        let onKeyPress: (KeyboardShortcut) -> Void
        let onKeyboardShortcut: ((CustomKeyboardShortcut.Key) -> Void)?
        let keyboardShortcuts: [CustomKeyboardShortcut]?

        @MainActor func makeUIView(context: Context) -> KeyPressableView {
            let view = KeyPressableView()
            view.onKeyPress = onKeyPress
            view.onKeyboardShortcut = onKeyboardShortcut
            view.keyboardShortcuts = onKeyboardShortcut != nil ? keyboardShortcuts : nil
            return view
        }

        func updateUIView(_ uiView: KeyPressableView, context: Context) {
            uiView.onKeyPress = onKeyPress
            uiView.onKeyboardShortcut = onKeyboardShortcut
            uiView.keyboardShortcuts = onKeyboardShortcut != nil ? keyboardShortcuts : nil
        }
    }

    private final class KeyPressableView: UIView {
        var onKeyPress: ((KeyboardShortcut) -> Void)?
        var onKeyboardShortcut: ((CustomKeyboardShortcut.Key) -> Void)?
        var keyboardShortcuts: [CustomKeyboardShortcut]?

        override var canBecomeFirstResponder: Bool { true }

        override var keyCommands: [UIKeyCommand]? {
            keyboardShortcuts?.compactMap { ks in
                ks.getUIKeyCommand(action: #selector(handleKeyPress(_:)))
            }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                becomeFirstResponder()
            }
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                if let key = press.key, let ke = getKeyEquivalent(key) {
                    for shortcut in keyboardShortcuts ?? [] {
                        if shortcut.key == ke.key && shortcut.modifiers == ke.modifiers {
                            Log.userInteraction.notice("Not handling key press because found shortcut with title \(shortcut.title, privacy: .public)")
                            super.pressesBegan(presses, with: event)
                            return
                        }
                    }
                    Log.userInteraction.notice("Handling key press \(ke.key.printableRepresentation, privacy: .public)")
                    onKeyPress?(ke)
                    handled = true
                }
            }

            if !handled {
                super.pressesBegan(presses, with: event)
            }
        }

        @objc func handleKeyPress(_ command: UIKeyCommand) {
            Log.userInteraction.notice("Getting keyboard shortcut \(command.title, privacy: .public) \(String(describing: command.input), privacy: .public)")
            if let key = CustomKeyboardShortcut.Key(rawValue: command.title) {
                onKeyboardShortcut?(key)
            }
        }
    }

    @MainActor
    func getKeyEquivalent(_ key: UIKey) -> KeyboardShortcut? {
        if let specialKey = specialKeyMapping(key: key) {
            return KeyboardShortcut(specialKey, modifiers: mapModifierFlags(key.modifierFlags))
        }

        guard let firstCharacter = key.characters.first else {
            return nil
        }

        let ke = KeyEquivalent(firstCharacter)
        return KeyboardShortcut(ke, modifiers: mapModifierFlags(key.modifierFlags))
    }

    @MainActor
    private func specialKeyMapping(key: UIKey) -> KeyEquivalent? {
        switch key.keyCode {
        case UIKeyboardHIDUsage.keyboardLeftArrow: .leftArrow
        case UIKeyboardHIDUsage.keyboardRightArrow: .rightArrow
        case UIKeyboardHIDUsage.keyboardDownArrow: .downArrow
        case UIKeyboardHIDUsage.keyboardUpArrow: .upArrow
        case UIKeyboardHIDUsage.keyboardReturnOrEnter: .return
        case UIKeyboardHIDUsage.keyboardTab: .tab
        case UIKeyboardHIDUsage.keyboardDeleteOrBackspace: .delete
        case UIKeyboardHIDUsage.keyboardEscape: .escape
        case UIKeyboardHIDUsage.keyboardHome: .home
        case UIKeyboardHIDUsage.keyboardPageUp: .pageUp
        case UIKeyboardHIDUsage.keyboardEnd: .end
        case UIKeyboardHIDUsage.keyboardPageDown: .pageDown
        case UIKeyboardHIDUsage.keyboardClear: .clear
        default: nil
        }
    }

    private func mapModifierFlags(_ flags: UIKeyModifierFlags) -> EventModifiers {
        var modifiers = EventModifiers()

        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.alternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.alphaShift) {
            modifiers.insert(.capsLock)
        }

        return modifiers
    }
#endif
