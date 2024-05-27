#if !os(macOS)
    import Foundation
    import OSLog
    import SwiftUI
    import UIKit

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "KeyboardMonitor"
    )

    struct OnKeyPressModifier: ViewModifier {
        let onKeyPress: (KeyboardShortcut) -> Void
        let enabled: Bool

        func body(content: Content) -> some View {
            if enabled {
                content.overlay(
                    KeyHandlingViewRepresentable(onKeyPress: onKeyPress)
                        .allowsHitTesting(false)
                )
            } else {
                content
            }
        }
    }

    extension View {
        func onKeyDown(_ onKeyPress: @escaping (KeyboardShortcut) -> Void, enabled: Bool = true) -> some View {
            modifier(OnKeyPressModifier(onKeyPress: onKeyPress, enabled: enabled))
        }
    }

    struct KeyHandlingViewRepresentable: UIViewRepresentable {
        var onKeyPress: (KeyboardShortcut) -> Void

        func makeUIView(context _: Context) -> KeyHandlingUIView {
            KeyHandlingUIView(onKeyPress: onKeyPress)
        }

        func updateUIView(_: KeyHandlingUIView, context _: Context) {}
    }

    class KeyHandlingUIView: UIView {
        var onKeyPress: (KeyboardShortcut) -> Void

        init(onKeyPress: @escaping (KeyboardShortcut) -> Void) {
            self.onKeyPress = onKeyPress
            super.init(frame: .zero)
            isUserInteractionEnabled = true
            becomeFirstResponder()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.becomeFirstResponder()
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            becomeFirstResponder()
        }

        override func resignFirstResponder() -> Bool {
            logger.info("Asked to resign first responder. Returning false")
            return false
        }

        override var canBecomeFirstResponder: Bool { true }

        override func pressesBegan(_ presses: Set<UIPress>, with _: UIPressesEvent?) {
            guard let press = presses.first, let key = press.key else { return }
            if let ke = getKeyEquivalent(key) {
                onKeyPress(ke)
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
