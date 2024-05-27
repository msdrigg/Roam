import Foundation
import SwiftUI

struct TopBar: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void

    var body: some View {
        HStack(spacing: globalButtonSpacing * 2) {
            Button(action: { action(.back) }, label: {
                Label("Back", systemImage: "arrow.left")
                    .frame(width: globalButtonWidth, height: globalButtonHeight)
            })
            #if !os(tvOS) && !os(watchOS)
            .customKeyboardShortcut(.back)
            #endif
            #if !os(visionOS)
            .sensoryFeedback(.impact, trigger: pressCounter(.back))
            #endif
            .symbolEffect(.bounce, value: pressCounter(.back))

            Button("Power On/Off", systemImage: "power", role: .destructive, action: { action(.power) })
                .font(.title)
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            #if !os(visionOS)
                .sensoryFeedback(.impact, trigger: pressCounter(.power))
            #endif
                .symbolEffect(.bounce, value: pressCounter(.power))
            #if !os(tvOS) && !os(watchOS)
                .customKeyboardShortcut(.power)
            #endif

            Button(action: { action(.home) }, label: {
                Label("Home", systemImage: "house")
                    .frame(width: globalButtonWidth, height: globalButtonHeight)
            })
            #if !os(tvOS) && !os(watchOS)
            .customKeyboardShortcut(.home)
            #endif
            #if !os(visionOS)
            .sensoryFeedback(.impact, trigger: pressCounter(.home))
            #endif
            .symbolEffect(.bounce, value: pressCounter(.home))
        }
    }
}
