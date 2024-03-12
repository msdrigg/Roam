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
    
    var body: some View {
        let buttons: [(String?, RemoteButton, String)?] = [
            nil, ("chevron.up", .up, "Up"), nil,
            ("chevron.left", .left, "Left"), (nil, .select, "Ok"), ("chevron.right", .right, "Right"),
            nil, ("chevron.down", .down, "Down"), nil
        ]
        return VStack(alignment: .center) {
            Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { col in
                            if let button = buttons[row * 3 + col] {
                                Button(action: {action(button.1)}) {
                                    if let systemImage = button.0 {
                                        Label(button.2, systemImage: systemImage)
                                            .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                                    } else {
                                        Text(button.2)
                                            .frame(width: BUTTON_WIDTH, height: BUTTON_HEIGHT)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                        
                                    }
                                }
                                .buttonStyle(.borderedProminent)
#if !os(visionOS)
                                .sensoryFeedback(.impact, trigger: pressCounter(button.1))
#endif
                                .symbolEffect(.bounce, value: pressCounter(button.1))
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
