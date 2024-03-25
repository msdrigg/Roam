import Foundation
import SwiftData
import AppIntents
import WidgetKit
import SwiftUI

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
        let currentDate = Date()
        
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
        let entry = DeviceChoiceTimelineEntity(date: currentDate, device: device, apps: apps)
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        return timeline
    }
    
    func placeholder(in context: Context) -> DeviceChoiceTimelineEntity {
        DeviceChoiceTimelineEntity(date: Date(), device: nil, apps: [])
    }
}
