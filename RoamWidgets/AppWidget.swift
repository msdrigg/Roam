import Foundation
import SwiftUI
import SwiftData
import AppIntents
import WidgetKit

#if !os(watchOS)
struct SmallAppWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.roam.app-links",
            intent: DeviceChoiceIntent.self,
            provider: RemoteControlProvider()
        ) { entry in
            SmallAppView(device: entry.device, apps: entry.apps, rows: 2)
                .containerBackground(Color("WidgetBackground"), for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}

#Preview("AppWidgetMid",as: WidgetFamily.systemSmall) {
    SmallAppWidget()
} timeline: {
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: getTestingDevices()[0].toAppEntity(),
        apps: getTestingAppLinks().map{$0.toAppEntityWithIcon()}
    )
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: nil,
        apps: []
    )
}
#endif

#if !os(macOS)
struct SmallerAppWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.roam.smaller-app-links",
            intent: DeviceChoiceIntent.self,
            provider: RemoteControlProvider()
        ) { entry in
            SmallAppView(device: entry.device, apps: Array(entry.apps.prefix(2)), rows: 1)
                .containerBackground(Color("WidgetBackground"), for: .widget)
        }
        .supportedFamilies([.accessoryRectangular])
    }
}

#Preview("AppWidgetSmall", as: WidgetFamily.accessoryRectangular) {
    SmallerAppWidget()
} timeline: {
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: getTestingDevices()[0].toAppEntity(),
        apps: Array(getTestingAppLinks().map{$0.toAppEntityWithIcon()}.prefix(2))
    )
    DeviceChoiceTimelineEntity (
        date: Date.now,
        device: nil,
        apps: []
    )
}
#endif
