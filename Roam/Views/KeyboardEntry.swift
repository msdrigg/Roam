//
//  KeyboardEntry.swift
//  Roam
//
//  Created by Scott Driggers on 10/20/23.
//

import Foundation
import SwiftUI

@available(iOS, introduced: 17.0)
struct KeyboardEntry: View {
    @Binding var str: String
    @FocusState private var keyboardFocused: Bool
    let onKeyPress:  (_ press: KeyPress) -> KeyPress.Result
    let leaving: Bool
    
    var body: some View {
        TextField("Enter some text...", text: $str)
            .focused($keyboardFocused)
            .onKeyPress{ key in onKeyPress(key)}
            .font(.body)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.fill.tertiary))
        .frame(height: 60)
        .onChange(of: leaving) {
            keyboardFocused = false
        }
        .onAppear {
            keyboardFocused = true
            str = ""
        }
        
    }
}
