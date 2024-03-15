import Foundation
import SwiftUI
    
struct TopBar: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    let onKeyPress: (KeyEquivalent) -> Void

    
    var body: some View {
        ZStack {
            KeyboardMonitor(onKeyPress: {key in onKeyPress(key)})
            HStack(spacing: BUTTON_SPACING * 2) {
                Spacer()
                Button(action: {action(.back)}) {
                    Label("Back", systemImage: "arrow.left")
                        .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                }
#if !os(tvOS) && !os(watchOS)
                .keyboardShortcut(.leftArrow)
#endif
#if !os(visionOS)
                .sensoryFeedback(.impact, trigger: pressCounter(.back))
#endif
                .symbolEffect(.bounce, value: pressCounter(.back))
                
                
                Button("Power On/Off", systemImage: "power", role: .destructive, action: {action(.power)})
                    .font(.title)
                    .foregroundStyle(.red)
                    .buttonStyle(.plain)
#if !os(visionOS)
                    .sensoryFeedback(.impact, trigger: pressCounter(.power))
#endif
                    .symbolEffect(.bounce, value: pressCounter(.power))
#if !os(tvOS) && !os(watchOS)
                    .keyboardShortcut(.return)
#endif
                
                
                Button(action: {action(.home)}) {
                    Label("Home", systemImage: "house")
                        .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                    
                }
#if !os(tvOS) && !os(watchOS)
                .keyboardShortcut("h")
#endif
#if !os(visionOS)
                .sensoryFeedback(.impact, trigger: pressCounter(.home))
#endif
                .symbolEffect(.bounce, value: pressCounter(.home))
                Spacer()
            }
        }
    }
}
