import AppIntents
import Foundation
import SwiftData
import SwiftUI
import WidgetKit

#if !os(watchOS)
    struct SmallDpadWidget: Widget {
        let dpad: [[RemoteButton?]] = [
            [
                .back, .up, .power,
            ],
            [
                .left, .select, .right,
            ],
            [
                .volumeDown, .down, .volumeUp,
            ],
        ]

        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.small-remote",
                intent: DeviceChoiceIntent.self,
                provider: SimpleRemoteControlProvider()
            ) { entry in
                SmallRemoteView(device: entry.device, controls: dpad)
                    .containerBackground(Color("WidgetBackground"), for: .widget)
            }
            .supportedFamilies([.systemSmall])
        }
    }

    struct SmallMediaWidget: Widget {
        let controls: [[RemoteButton?]] = [
            [
                .instantReplay, .power, .options,
            ],
            [
                .rewind, .playPause, .fastForward,
            ],
            [
                .volumeDown, .mute, .volumeUp,
            ],
        ]

        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.media-remote",
                intent: DeviceChoiceIntent.self,
                provider: SimpleRemoteControlProvider()
            ) { entry in
                SmallRemoteView(device: entry.device, controls: controls)
                    .containerBackground(Color("WidgetBackground"), for: .widget)
            }
            .supportedFamilies([.systemSmall])
        }
    }

    #Preview(as: WidgetFamily.systemSmall) {
        SmallDpadWidget()
    } timeline: {
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: getTestingDevices()[0].toAppEntity(),
            apps: getTestingAppLinks().map { $0.toAppEntityWithIcon() }
        )
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: nil,
            apps: []
        )
    }

    #Preview(as: WidgetFamily.systemSmall) {
        SmallMediaWidget()
    } timeline: {
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: getTestingDevices()[0].toAppEntity(),
            apps: getTestingAppLinks().map { $0.toAppEntityWithIcon() }
        )
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: nil,
            apps: []
        )
    }
#endif

#if !os(macOS)
    struct SmallVolumeWidget: Widget {
        let dpad: [[RemoteButton?]] = [[
            .volumeDown, .mute, .volumeUp,
        ]]

        var body: some WidgetConfiguration {
            AppIntentConfiguration(
                kind: "com.msdrigg.roam.small-volume-remote",
                intent: DeviceChoiceIntent.self,
                provider: SimpleRemoteControlProvider()
            ) { entry in
                SmallRemoteView(device: entry.device, controls: dpad)
                    .containerBackground(Color("WidgetBackground"), for: .widget)
            }
            .supportedFamilies([.accessoryRectangular])
        }
    }

    #Preview(as: WidgetFamily.accessoryRectangular) {
        SmallVolumeWidget()
    } timeline: {
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: getTestingDevices()[0].toAppEntity(),
            apps: getTestingAppLinks().map { $0.toAppEntityWithIcon() }
        )
        DeviceChoiceTimelineEntity(
            date: Date.now,
            device: nil,
            apps: []
        )
    }
#endif
