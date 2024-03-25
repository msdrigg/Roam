//
//  CenterController.swift
//  Roam
//
//  Created by Scott Driggers on 10/20/23.
//

import Foundation
import SwiftUI

struct CenterController: View {
    let pressCounter: (RemoteButton) -> Int
    let action: (RemoteButton) -> Void
    @State private var pressCount: [RemoteButton: Int] = [:]
    
    var body: some View {
        let buttons: [(String?, RemoteButton, String)?] = [
            nil, ("chevron.up", .up, "Up"), nil,
            ("chevron.left", .left, "Left"), (nil, .select, "Ok"), ("chevron.right", .right, "Right"),
            nil, ("chevron.down", .down, "Down"), nil
        ]
        return VStack(alignment: .center) {
            Grid(horizontalSpacing: BUTTON_SPACING/5, verticalSpacing: BUTTON_SPACING/5) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { col in
                            if let button = buttons[row * 3 + col] {
                                Button(action: {action(button.1)}) {
                                    if let systemImage = button.0 {
                                        Label(button.2, systemImage: systemImage)
                                            .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                                            .symbolEffect(.bounce, value: pressCounter(button.1))
                                    } else {
                                        Text(button.2)
                                            .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                            .scaleEffect((pressCount[button.1] ?? 0) != pressCounter(button.1) ? 1.15 : 1.0)
                                            .animation(.interpolatingSpring(stiffness: 80, damping: 5), value: (pressCount[button.1] ?? 0) != pressCounter(button.1))
                                            .onChange(of: pressCounter(button.1)) { _, newValue in
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                                    pressCount[button.1] = newValue
                                                }
                                            }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
#if !os(visionOS)
                                .sensoryFeedback(.impact, trigger: pressCounter(button.1))
#endif
                            } else {
                                Spacer()
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: BUTTON_WIDTH * 3 + 6, maxHeight: BUTTON_HEIGHT * 3 + 6)
        }
        .id("controllerGrid")
    }
}
