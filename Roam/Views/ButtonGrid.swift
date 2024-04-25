import Foundation
import SwiftUI

struct ButtonGrid: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    let enabled: Set<RemoteButton>
    let disabled: Set<RemoteButton>

    var body: some View {
        let buttonRows: [[(String, String, RemoteButton, KeyEquivalent?)]] = [
            [("Replay", "arrow.uturn.backward", .instantReplay, nil),
             ("Options", "asterisk", .options, nil),
             ("Headphones mode", "headphones", .headphonesMode, nil)],
            [("Rewind", "backward", .rewind, nil),
             ("Play/Pause", "playpause", .playPause, "p"),
             ("Fast Forward", "forward", .fastForward, nil)],
            [("Volume Down", "speaker.minus", .volumeDown, .downArrow),
             ("Mute", "speaker.slash", .mute, "m"),
             ("Volume Up", "speaker.plus", .volumeUp, .upArrow)],
        ]
        return Grid(horizontalSpacing: globalButtonSpacing, verticalSpacing: globalButtonSpacing) {
            ForEach(buttonRows, id: \.first?.0) { row in
                GridRow {
                    ForEach(row, id: \.0) { button in
                        let view = Button(action: { action(button.2) }, label: {
                            Label(button.0, systemImage: button.1)
                                .frame(width: globalButtonWidth, height: globalButtonHeight)
                        })
                        .disabled(disabled.contains(button.2))
                        .symbolEffect(.pulse, isActive: enabled.contains(button.2))
                        #if !os(visionOS)
                            .sensoryFeedback(.impact, trigger: pressCounter(button.2))
                        #endif
                            .symbolEffect(.bounce, value: pressCounter(button.2))
                        #if !os(tvOS) && !os(watchOS)
                            if let shortcut = button.3 {
                                view
                                    .keyboardShortcut(shortcut)
                            } else {
                                view
                            }
                        #else
                            view
                        #endif
                    }
                }
            }
        }
    }
}
