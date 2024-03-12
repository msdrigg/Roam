import Foundation
import SwiftUI
    
struct TopBar: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    let onKeyPress: (KeyEquivalent) -> Void

    
    var body: some View {
        ZStack {
            KeyboardMonitor(onKeyPress: {key in onKeyPress(key)})

            HStack(spacing: 20) {
                Button(action: {action(.back)}) {
                    Label("Back", systemImage: "arrow.left")
                        .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                }
                .keyboardShortcut(.leftArrow)
                .sensoryFeedback(.impact, trigger: pressCounter(.back))
                .symbolEffect(.bounce, value: pressCounter(.back))
                
                Button("Power On/Off", systemImage: "power", role: .destructive, action: {action(.power)})
                    .font(.title)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact, trigger: pressCounter(.power))
                    .symbolEffect(.bounce, value: pressCounter(.power))
                    .keyboardShortcut(.return)
                
                
                Button(action: {action(.home)}) {
                    Label("Home", systemImage: "house")
                        .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                    
                }
                .keyboardShortcut("h")
                .sensoryFeedback(.impact, trigger: pressCounter(.home))
                .symbolEffect(.bounce, value: pressCounter(.home))
            }
        }
    }
}
