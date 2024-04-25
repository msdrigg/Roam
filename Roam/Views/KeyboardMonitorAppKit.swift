#if os(macOS)
    import AppKit
    import Foundation
    import OSLog
    import SwiftUI

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: "KeyboardMonitor"
    )

    struct OnKeyPressModifier: ViewModifier {
        let onKeyPress: (KeyEquivalent) -> Void
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
        func onKeyDown(_ onKeyPress: @escaping (KeyEquivalent) -> Void, enabled: Bool = true) -> some View {
            modifier(OnKeyPressModifier(onKeyPress: onKeyPress, enabled: enabled))
        }
    }

    struct KeyHandlingViewRepresentable: NSViewRepresentable {
        var onKeyPress: (KeyEquivalent) -> Void

        func makeNSView(context _: Context) -> KeyHandlingView {
            KeyHandlingView(onKeyPress: onKeyPress)
        }

        func updateNSView(_: KeyHandlingView, context _: Context) {}

        class KeyHandlingView: NSView {
            var onKeyPress: (KeyEquivalent) -> Void
            var observerTokens: [Any] = []

            init(onKeyPress: @escaping (KeyEquivalent) -> Void) {
                self.onKeyPress = onKeyPress
                super.init(frame: .zero)
                setupObservers()
                becomeFirstResponder()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.becomeFirstResponder()
                    NSApp.mainWindow?.makeFirstResponder(self)
                }
            }

            override func resignFirstResponder() -> Bool {
                logger.info("Asked to resign first responder. Returning false")
                return false
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }

            override var acceptsFirstResponder: Bool { true }

            override func keyDown(with event: NSEvent) {
                guard let ke = getKeyEquivalent(from: event) else {
                    return
                }

                onKeyPress(ke)
            }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                becomeFirstResponder()
                window?.makeFirstResponder(self)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    if let self {
                        becomeFirstResponder()
                        NSApp.mainWindow?.makeFirstResponder(self)
                    }
                }
            }

            override func viewDidMoveToSuperview() {
                super.viewDidMoveToSuperview()
                becomeFirstResponder()

                window?.makeFirstResponder(self)
            }

            deinit {
                for token in observerTokens {
                    NotificationCenter.default.removeObserver(token)
                }
            }

            private func windowDidBecomeMain() {
                window?.makeFirstResponder(self)
            }

            private func setupObservers() {
                let token = NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeMainNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.windowDidBecomeMain()
                }
                observerTokens.append(token)
            }
        }
    }

    func getKeyEquivalent(from event: NSEvent) -> KeyEquivalent? {
        guard event.type == .keyDown else { return nil }

        if let specialKey = specialKeyMapping(forKeyCode: event.keyCode) {
            return specialKey
        }

        let characters: String
        if let regularCharacters = event.characters {
            characters = regularCharacters
        } else if let keyEquivalent = specialKeyMapping(forKeyCode: event.keyCode) {
            return keyEquivalent
        } else {
            return nil
        }

        guard let firstCharacter = characters.first else { return nil }

        return KeyEquivalent(firstCharacter)
    }

    private func specialKeyMapping(forKeyCode keyCode: UInt16) -> KeyEquivalent? {
        switch keyCode {
        case 123: .leftArrow
        case 124: .rightArrow
        case 125: .downArrow
        case 126: .upArrow
        case 36: .return
        case 48: .tab
        case 51: .delete
        case 53: .escape
        case 115: .home
        case 116: .pageUp
        case 119: .end
        case 121: .pageDown
        case 117: .clear

        default: nil
        }
    }

#endif
