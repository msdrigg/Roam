import Foundation
import SwiftUI

struct ButtonGrid: View  {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    
    var body: some View {
        let buttonRows: [[(String, String, RemoteButton, KeyEquivalent?, Bool)]] = [
            [("Replay", "arrow.uturn.backward", .instantReplay, nil, false),
             ("Options", "asterisk", .options, nil, false),
             ("Private Listening", "headphones", .enter, nil, true)],
            [("Rewind", "backward", .rewind, nil, false),
             ("Play/Pause", "playpause", .playPause, nil, false),
             ("Fast Forward", "forward", .fastForward, nil, false)],
            [("Volume Down", "speaker.minus", .volumeDown, .downArrow, false),
             ("Mute", "speaker.slash", .mute, "m", false),
             ("Volume Up", "speaker.plus", .volumeUp, .upArrow, false)]
        ]
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(buttonRows, id: \.first?.0) { row in
                GridRow {
                    ForEach(row, id: \.0) { button in
                        let view = Button(action: {action(button.2)}) {
                            Label(button.0, systemImage: button.1)
                                .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                        }
                            .disabled(button.4)
                            .sensoryFeedback(.impact, trigger: pressCounter(button.2))
                            .symbolEffect(.bounce, value: pressCounter(button.2))
                        if let ks = button.3 {
                            view
                                .keyboardShortcut(ks)
                        } else {
                            view
                        }
                    }
                }
            }
        }
    }
}
