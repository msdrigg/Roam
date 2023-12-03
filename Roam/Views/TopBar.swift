import Foundation
import SwiftUI
    
struct TopBar: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    let onKeyPress: (KeyEquivalent) -> KeyPress.Result

    
    var body: some View {
        HStack(spacing: 20) {
            Button(action: {action(.back)}) {
                Label("Back", systemImage: "arrow.left")
                    .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
            }
            .keyboardShortcut(.leftArrow)
            .sensoryFeedback(.impact, trigger: pressCounter(.back))
            .symbolEffect(.bounce, value: pressCounter(.back))
            
#if os(macOS)
            KeyboardMonitor(onKeyPress: {key in onKeyPress(key.key)})
            // Do this so the focus outline on macOS matches
                .offset(y: 7)
            
#elseif os(iOS)
            Button("Power On/Off", systemImage: "power", role: .destructive, action: {action(.power)})
            .font(.title)
            .foregroundStyle(.red)
            .buttonStyle(.plain)
            .sensoryFeedback(.impact, trigger: pressCounter(.power))
            .symbolEffect(.bounce, value: pressCounter(.power))
#endif
            
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
