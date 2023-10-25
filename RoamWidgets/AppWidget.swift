import Foundation
import SwiftUI
import SwiftData
import AppIntents
import WidgetKit

struct SmallAppWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: "com.msdrigg.roam.app-links",
            intent: DeviceChoiceIntent.self,
            provider: RemoteControlProvider()
        ) { entry in
            SmallAppView(device: entry.device, apps: entry.device?.apps ?? [])
                .containerBackground(Color("WidgetBackground"), for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}

#Preview(as: WidgetFamily.systemSmall) {
    SmallAppWidget()
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
