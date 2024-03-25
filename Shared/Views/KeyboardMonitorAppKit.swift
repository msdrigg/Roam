#if os(macOS)
import Foundation
import SwiftUI
import AppKit

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
        self.modifier(OnKeyPressModifier(onKeyPress: onKeyPress, enabled: enabled))
    }
}


struct KeyHandlingViewRepresentable: NSViewRepresentable {
    var onKeyPress: (KeyEquivalent) -> Void

    func makeNSView(context: Context) -> KeyHandlingView {
        KeyHandlingView(onKeyPress: onKeyPress)
    }

    func updateNSView(_ nsView: KeyHandlingView, context: Context) {}

    class KeyHandlingView: NSView {
        var onKeyPress: (KeyEquivalent) -> Void
        var observerTokens: [Any] = []

        init(onKeyPress: @escaping (KeyEquivalent) -> Void) {
            self.onKeyPress = onKeyPress
            super.init(frame: .zero)
            self.setupObservers()
            self.becomeFirstResponder()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.becomeFirstResponder()
                NSApp.mainWindow?.makeFirstResponder(self)
            }
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { return true }
        
        override func keyDown(with event: NSEvent) {
            guard let ke = getKeyEquivalent(from: event) else {
                return
            }
            
            onKeyPress(ke)
        }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.becomeFirstResponder()
            window?.makeFirstResponder(self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                if let self {
                    self.becomeFirstResponder()
                    NSApp.mainWindow?.makeFirstResponder(self)
                }
            }
        }
        
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            self.becomeFirstResponder()

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
            let token = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeMainNotification, object: self.window, queue: .main) { [weak self] _ in
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
        case 123: return .leftArrow
        case 124: return .rightArrow
        case 125: return .downArrow
        case 126: return .upArrow
        case 36:  return .return
        case 48:  return .tab
        case 51:  return .delete
        case 53:  return .escape
        case 115: return .home
        case 116: return .pageUp
        case 119: return .end
        case 121: return .pageDown
        case 117: return .clear

        default: return nil
    }
}

#endif
