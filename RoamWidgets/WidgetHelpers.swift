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

struct SimpleRemoteControlProvider: AppIntentTimelineProvider {
    
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
        let device = if configuration.manuallySelectDevice, let device = configuration.device {
            device
        } else {
            await fetchSelectedDevice(modelContainer: modelContainer)
        }
        let apps: [AppLinkAppEntity] = if let udn = device?.udn{
            await fetchSelectedAppLinks(modelContainer: modelContainer, deviceId: udn)
        } else {
            []
        }
        
        let entry = DeviceChoiceTimelineEntity(date: Date(), device: device, apps: apps)
        return entry
    }
    
    func timeline(for configuration: DeviceChoiceIntent, in context: Context) async -> Timeline<DeviceChoiceTimelineEntity> {
        let device = if configuration.manuallySelectDevice, let device = configuration.device {
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


struct AppChoiceRemoteControlProvider: AppIntentTimelineProvider {
    typealias Intent = DeviceAndAppChoiceIntent
    typealias Entry = DeviceChoiceTimelineEntity
    
    private let modelContainer: ModelContainer
    
    init() {
        modelContainer = getSharedModelContainer()
    }
    
    func recommendations() -> [AppIntentRecommendation<DeviceAndAppChoiceIntent>] {
        return [
            AppIntentRecommendation(intent: DeviceAndAppChoiceIntent(), description: Text("Control your Roku!"))
        ]
    }

    func snapshot(for configuration: DeviceAndAppChoiceIntent, in context: Context) async -> DeviceChoiceTimelineEntity {
        let device = if configuration.manuallySelectDevice, let device = configuration.device {
            device
        } else {
            await fetchSelectedDevice(modelContainer: modelContainer)
        }
        var apps: [AppLinkAppEntity] = []
        if let udn = device?.udn {
            var loadedApps = await fetchSelectedAppLinks(modelContainer: modelContainer, deviceId: udn)
            if configuration.manuallySelectApps {
                if let app1 = configuration.app1 {
                    loadedApps.insert(app1, at: 0)
                }
                if let app2 = configuration.app2 {
                    loadedApps.insert(app2, at: 1)
                }
                if let app3 = configuration.app3 {
                    loadedApps.insert(app3, at: 2)
                }
                if let app4 = configuration.app4 {
                    loadedApps.insert(app4, at: 3)
                }
            }
            apps = loadedApps
        }
        
        let entry = DeviceChoiceTimelineEntity(date: Date(), device: device, apps: apps)
        return entry
    }
    
    func timeline(for configuration: DeviceAndAppChoiceIntent, in context: Context) async -> Timeline<DeviceChoiceTimelineEntity> {
        let device = if configuration.manuallySelectDevice, let device = configuration.device {
            device
        } else {
            await fetchSelectedDevice(modelContainer: modelContainer)
        }
        
        var apps: [AppLinkAppEntity] = []
        if let udn = device?.udn {
            var loadedApps = await fetchSelectedAppLinks(modelContainer: modelContainer, deviceId: udn)
            if configuration.manuallySelectApps {
                if let app1 = configuration.app1 {
                    loadedApps.insert(app1, at: 0)
                }
                if let app2 = configuration.app2 {
                    loadedApps.insert(app2, at: 1)
                }
                if let app3 = configuration.app3 {
                    loadedApps.insert(app3, at: 2)
                }
                if let app4 = configuration.app4 {
                    loadedApps.insert(app4, at: 3)
                }
            }
            apps = loadedApps
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
