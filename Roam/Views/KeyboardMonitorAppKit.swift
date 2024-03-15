//
//  KeyboardMonitor.swift
//  Roam
//
//  Created by Scott Driggers on 10/20/23.
//

#if os(macOS)
import Foundation
import SwiftUI
import AppKit

struct KeyboardMonitor: View {
    let onKeyPress: (KeyEquivalent) -> Void

    var body: some View {
        Spacer().frame(maxWidth: 20, maxHeight: 20)
        .background(KeyHandlingViewRepresentable(onKeyPress: onKeyPress))
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

        init(onKeyPress: @escaping (KeyEquivalent) -> Void) {
            self.onKeyPress = onKeyPress
            super.init(frame: .zero)
            self.becomeFirstResponder()
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
