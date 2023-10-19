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

struct MediumRemoteWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.betterremote.medium-remote",
            intent: DeviceChoiceIntent.self,
            provider: RemoteControlProvider()
        ) { entry in
            MediumRemoteView(device: entry.device)
        }
        .supportedFamilies([.systemMedium])
    }
}

struct MediumRemoteView: View {
    var device: DeviceAppEntity?
    
    let dPad: [[RemoteButton?]] = [
        [.back, .up, .home],
        [.left, .select, .right],
        [nil, .down, nil]
    ]
    let controlGrid: [[RemoteButton?]] = [
        [.instantReplay, .power, .options],
        [.rewind, .playPause, .fastForward],
        [.mute, .volumeDown, .volumeUp]
    ]
    
    var body: some View {
        HStack {
            SmallRemoteView(device: device, controls: dPad)
            Spacer()
            SmallRemoteView(device: device, controls: controlGrid)
        }
        .containerBackground(Color("WidgetBackground"), for: .widget)
    }
}


#Preview(as: WidgetFamily.systemMedium) {
    MediumRemoteWidget()
} timeline: {
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: getTestingDevices()[0].toAppEntity()
    )
}
