import Foundation
import SwiftData
import AppIntents
import WidgetKit
import SwiftUI
import OSLog

struct DeviceChoiceTimelineEntity: TimelineEntry {
    var date: Date
    var device: DeviceAppEntity?
    var apps: [AppLinkAppEntity]
}

struct RemoteControlProvider: AppIntentTimelineProvider {
    
    typealias Intent = DeviceChoiceIntent
    typealias Entry = DeviceChoiceTimelineEntity
    
    private let modelContainer: ModelContainer
    
    init() {
        modelContainer = getSharedModelContainer()
    }
    
    func recommendations() -> [AppIntentRecommendation<DeviceChoiceIntent>] {
        return [
            AppIntentRecommendation(intent: DeviceChoiceIntent(), description: Text("Control your Roku!"))
        ]
    }

    func snapshot(for configuration: DeviceChoiceIntent, in context: Context) async -> DeviceChoiceTimelineEntity {
        let device = if !configuration.useDefaultDevice, let device = configuration.device {
            device
        } else {
            await fetchSelectedDevice(modelContainer: modelContainer)
        }
        let apps: [AppLinkAppEntity] = if let udn = device?.udn{
            await fetchSelectedAppLinks(modelContainer: modelContainer, deviceId: udn)
        } else {
            []
        }
        
        let entry = DeviceChoiceTimelineEntity(date: Date(), device: configuration.useDefaultDevice ? nil : device, apps: apps)
        return entry
    }
    
    func timeline(for configuration: DeviceChoiceIntent, in context: Context) async -> Timeline<DeviceChoiceTimelineEntity> {
        let device = if !configuration.useDefaultDevice, let device = configuration.device {
            device
        } else {
            await fetchSelectedDevice(modelContainer: modelContainer)
        }
        
        let apps: [AppLinkAppEntity] = if let udn = device?.udn {
            await fetchSelectedAppLinks(modelContainer: modelContainer, deviceId: udn)
        } else {
            []
        }
        let entryNow = DeviceChoiceTimelineEntity(date: Date.now, device: device, apps: apps)
        let entryLater = DeviceChoiceTimelineEntity(date: Date.now + 86400, device: device, apps: apps)
        let timeline = Timeline(entries: [entryNow, entryLater], policy: .atEnd)
        return timeline
    }
    
    func placeholder(in context: Context) -> DeviceChoiceTimelineEntity {
        DeviceChoiceTimelineEntity(date: Date(), device: nil, apps: [])
    }
}
