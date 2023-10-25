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
    @State var strSent: String = ""
    @FocusState private var keyboardFocused: Bool
    let onKeyPress:  (_ press: KeyEquivalent) -> Void
    let leaving: Bool
    
    var body: some View {
        TextField("Enter some text...", text: $str)
            .focused($keyboardFocused)
            .font(.body)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 8).fill(.fill.tertiary))
        .frame(height: 60)
        .onChange(of: str) {
            if str.count < strSent.count {
                onKeyPress(KeyEquivalent.delete)
            } else if str.count > strSent.count {
                if let char = str.unicodeScalars.last {
                    onKeyPress(KeyEquivalent(Character(char)))
                }
            }
            
            strSent = str
        }
        .onChange(of: leaving) {
            keyboardFocused = false
        }
        .onAppear {
            keyboardFocused = true
            str = ""
            strSent = ""
        }
        
    }
}
