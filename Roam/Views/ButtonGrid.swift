import Foundation
import SwiftUI


struct ButtonGrid: View  {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    let enabled: Set<RemoteButton>
    let disabled: Set<RemoteButton>
    
    var body: some View {
        let buttonRows: [[(String, String, RemoteButton, KeyEquivalent?)]] = [
            [("Replay", "arrow.uturn.backward", .instantReplay, nil),
             ("Options", "asterisk", .options, nil),
             ("Private Listening", "headphones", .privateListening, nil)],
            [("Rewind", "backward", .rewind, nil),
             ("Play/Pause", "playpause", .playPause, "p"),
             ("Fast Forward", "forward", .fastForward, nil)],
            [("Volume Down", "speaker.minus", .volumeDown, .downArrow),
             ("Mute", "speaker.slash", .mute, "m"),
             ("Volume Up", "speaker.plus", .volumeUp, .upArrow)]
        ]
        return Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            ForEach(buttonRows, id: \.first?.0) { row in
                GridRow {
                    ForEach(row, id: \.0) { button in
                        let view = Button(action: {action(button.2)}) {
                            Label(button.0, systemImage: button.1)
                                .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)

                        }
                            .disabled(disabled.contains(button.2))
                            .symbolEffect(.pulse, isActive: enabled.contains(button.2))
#if !os(visionOS)
                            .sensoryFeedback(.impact, trigger: pressCounter(button.2))
#endif
                            .symbolEffect(.bounce, value: pressCounter(button.2))
#if os(iOS) || os(macOS)
                        if let ks = button.3 {
                            view
                                .keyboardShortcut(ks)
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

extension View {
    /// Applies the given transform if the given condition evaluates to `true`.
    /// - Parameters:
    ///   - condition: The condition to evaluate.
    ///   - transform: The transform to apply to the source `View`.
    /// - Returns: Either the original `View` or the modified `View` if the condition is `true`.
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
