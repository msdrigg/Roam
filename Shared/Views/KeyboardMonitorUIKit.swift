//
//  KeyboardMonitor.swift
//  Roam
//
//  Created by Scott Driggers on 10/20/23.
//

#if !os(macOS)
import Foundation
import SwiftUI
import UIKit

import SwiftUI

struct KeyboardMonitor: View {
    let onKeyPress: (KeyEquivalent) -> Void

    var body: some View {
        KeyHandlingViewRepresentable(onKeyPress: onKeyPress)
            .frame(width: 0, height: 0, alignment: .center)
    }
}

struct KeyHandlingViewRepresentable: UIViewRepresentable {
    var onKeyPress: (KeyEquivalent) -> Void

    func makeUIView(context: Context) -> KeyHandlingUIView {
        KeyHandlingUIView(onKeyPress: onKeyPress)
    }

    func updateUIView(_ uiView: KeyHandlingUIView, context: Context) {}
}

class KeyHandlingUIView: UIView {
    var onKeyPress: (KeyEquivalent) -> Void

    init(onKeyPress: @escaping (KeyEquivalent) -> Void) {
        self.onKeyPress = onKeyPress
        super.init(frame: .zero)
        self.isUserInteractionEnabled = true
        self.becomeFirstResponder()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            self.becomeFirstResponder()
        }
    }

    override var canBecomeFirstResponder: Bool { return true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let press = presses.first, let key = press.key else { return }
        if let ke = getKeyEquivalent(key) {
            onKeyPress(ke)
        }
    }
}

func getKeyEquivalent(_ key: UIKey) -> KeyEquivalent? {
    if let specialKey = specialKeyMapping(key: key) {
        return specialKey
    }
    
    guard let firstCharacter = key.characters.first else {
        return nil
    }

    return KeyEquivalent(firstCharacter)
}

private func specialKeyMapping(key: UIKey) -> KeyEquivalent? {
    switch key.keyCode {
    case UIKeyboardHIDUsage.keyboardLeftArrow: return .leftArrow
    case UIKeyboardHIDUsage.keyboardRightArrow: return .rightArrow
    case UIKeyboardHIDUsage.keyboardDownArrow: return .downArrow
    case UIKeyboardHIDUsage.keyboardUpArrow: return .upArrow
    case UIKeyboardHIDUsage.keyboardReturnOrEnter: return .return
    case UIKeyboardHIDUsage.keyboardTab: return .tab
    case UIKeyboardHIDUsage.keyboardDeleteOrBackspace: return .delete
    case UIKeyboardHIDUsage.keyboardEscape: return .escape
    case UIKeyboardHIDUsage.keyboardHome: return .home
    case UIKeyboardHIDUsage.keyboardPageUp: return .pageUp
    case UIKeyboardHIDUsage.keyboardEnd: return .end
    case UIKeyboardHIDUsage.keyboardPageDown: return .pageDown
    case UIKeyboardHIDUsage.keyboardClear: return .clear
    default: return nil
    }
}

#endif
