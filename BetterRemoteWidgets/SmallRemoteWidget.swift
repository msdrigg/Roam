//
//  SmallButtons.swift
//  BetterRemote
//
//  Created by Scott Driggers on 10/17/23.
//

import Foundation
import SwiftUI
import SwiftData
import AppIntents
import WidgetKit

struct SmallDpadWidget: Widget {
    let dpad: [[RemoteButton?]] = [
        [
            .back, .up, .power
        ],
        [
            .left, .select, .right
        ],
        [
            .volumeDown, .down, .volumeUp
        ]
    ]
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.betterremote.small-remote",
            intent: DeviceChoiceIntent.self,
            provider: RemoteControlProvider()
        ) { entry in
            SmallRemoteView(device: entry.device, controls: dpad)
                .containerBackground(Color("WidgetBackground"), for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}

func remoteButtonStyle(_ button: RemoteButton) -> any PrimitiveButtonStyle {
    switch button {
    case .power:
            return .plain
    case .up, .down, .left, .right, .select:
        return .plain
    default:
        return .bordered
    }
}

struct SmallMediaWidget: Widget {
    let controls: [[RemoteButton?]] = [
        [
            .instantReplay, .power, .options
        ],
        [
            .rewind, .playPause, .fastForward
        ],
        [
            .volumeDown, .mute, .volumeUp
        ]
    ]
    
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.betterremote.media-remote",
            intent: DeviceChoiceIntent.self,
            provider: RemoteControlProvider()
        ) { entry in
            SmallRemoteView(device: entry.device, controls: controls)
                .containerBackground(Color("WidgetBackground"), for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}

struct SmallRemoteView: View {
    let device: DeviceAppEntity?
    let controls: [[RemoteButton?]]
    
    var body: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            ForEach(controls, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { button in
                        if let button = button {
                            if button == .power {
                                Button(intent: ButtonPressIntent(button, device: device)) {
                                    button.label
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            } else if [.up, .down, .left, .right, .select].contains(button) {
                                Button(intent: ButtonPressIntent(button, device: device)) {
                                    button.label
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }.buttonStyle(.borderedProminent)
                            } else {
                                Button(intent: ButtonPressIntent(button, device: device)) {
                                    button.label
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                            }
                        } else {
                            Spacer()
                        }
                    }
                }
            }
        }
        .fontDesign(.rounded)
        .font(.body.bold())
        .buttonBorderShape(.roundedRectangle)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.iconOnly)
        .tint(Color("AccentColor"))
    }
}


#Preview(as: WidgetFamily.systemSmall) {
    SmallDpadWidget()
} timeline: {
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: getTestingDevices()[0].toAppEntity()
    )
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: nil
    )
}

#Preview(as: WidgetFamily.systemSmall) {
    SmallMediaWidget()
} timeline: {
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: getTestingDevices()[0].toAppEntity()
    )
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: nil
    )
}
