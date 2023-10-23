//
//  KeyboardMonitor.swift
//  Roam
//
//  Created by Scott Driggers on 10/20/23.
//

import Foundation
import SwiftUI

@available(macOS, introduced: 14.0)
struct KeyboardMonitor: View {
    @FocusState private var keyboardMonitorFocused: Bool
    let onKeyPress: (KeyPress) -> KeyPress.Result
    
    var body: some View {
        Button(action: {}) {
            Label("Keyboard", systemImage: "keyboard")
                .labelStyle(.iconOnly)
        }
        .font(.headline)
        // Do this so the focus outline on macos matches
        .offset(y: -7)
        #if os(macOS)
        .buttonStyle(.accessoryBar)
        #endif
        .focusable()
        .focused($keyboardMonitorFocused)
        .onKeyPress { key in
            return onKeyPress(key)
        }
        .onAppear {
            keyboardMonitorFocused = true
        }
    }
}
