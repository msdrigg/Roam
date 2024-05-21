import AppIntents
import Foundation
import OSLog
import SwiftData
import SwiftUI
import WidgetKit

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
        [
            AppIntentRecommendation(intent: DeviceChoiceIntent(), description: Text("Control your Roku!")),
        ]
    }

    func snapshot(for configuration: DeviceChoiceIntent, in _: Context) async -> DeviceChoiceTimelineEntity {
        let modelContainer = getSharedModelContainer()
        let dataHandler = DataHandler(modelContainer: modelContainer)

        var targetDevice = configuration.selectedDevice
        if targetDevice == nil {
            targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
        }
        
        let apps: [AppLinkAppEntity] = if let udn = targetDevice?.udn {
            (try? await dataHandler.appEntities(deviceUid: udn)) ?? []
        } else {
            []
        }

        let entry = DeviceChoiceTimelineEntity(date: Date(), device: targetDevice, apps: apps)
        return entry
    }

    func timeline(for configuration: DeviceChoiceIntent, in _: Context) async -> Timeline<DeviceChoiceTimelineEntity> {
        let modelContainer = getSharedModelContainer()
        let dataHandler = DataHandler(modelContainer: modelContainer)

        var targetDevice = configuration.selectedDevice
        if targetDevice == nil {
            targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
        }

        let apps: [AppLinkAppEntity] = if let udn = targetDevice?.udn {
            (try? await dataHandler.appEntities(deviceUid: udn)) ?? []
        } else {
            []
        }
        let entryNow = DeviceChoiceTimelineEntity(date: Date.now, device: targetDevice, apps: apps)
        let entryLater = DeviceChoiceTimelineEntity(date: Date.now + 86400, device: targetDevice, apps: apps)
        let timeline = Timeline(entries: [entryNow, entryLater], policy: .atEnd)
        return timeline
    }

    func placeholder(in _: Context) -> DeviceChoiceTimelineEntity {
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
        [
            AppIntentRecommendation(intent: DeviceAndAppChoiceIntent(), description: Text("Control your Roku!")),
        ]
    }

    func snapshot(for configuration: DeviceAndAppChoiceIntent, in _: Context) async -> DeviceChoiceTimelineEntity {
        let modelContainer = getSharedModelContainer()
        let dataHandler = DataHandler(modelContainer: modelContainer)

        var targetDevice = configuration.selectedDevice
        if targetDevice == nil {
            targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
        }
        
        var apps: [AppLinkAppEntity] = []
        if let udn = targetDevice?.udn {
            var loadedApps = (try? await dataHandler.appEntities(deviceUid: udn)) ?? []
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

        let entry = DeviceChoiceTimelineEntity(date: Date(), device: targetDevice, apps: apps)
        return entry
    }

    func timeline(for configuration: DeviceAndAppChoiceIntent,
                  in _: Context) async -> Timeline<DeviceChoiceTimelineEntity>
    {
        let modelContainer = getSharedModelContainer()
        let dataHandler = DataHandler(modelContainer: modelContainer)

        var targetDevice = configuration.selectedDevice
        if targetDevice == nil {
            targetDevice = await dataHandler.fetchSelectedDeviceAppEntity()
        }

        var apps: [AppLinkAppEntity] = []
        if let udn = targetDevice?.udn {
            var loadedApps = (try? await dataHandler.appEntities(deviceUid: udn)) ?? []
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
        let entryNow = DeviceChoiceTimelineEntity(date: Date.now, device: targetDevice, apps: apps)
        let entryLater = DeviceChoiceTimelineEntity(date: Date.now + 86400, device: targetDevice, apps: apps)
        let timeline = Timeline(entries: [entryNow, entryLater], policy: .atEnd)
        return timeline
    }

    func placeholder(in _: Context) -> DeviceChoiceTimelineEntity {
        DeviceChoiceTimelineEntity(date: Date(), device: nil, apps: [])
    }
}
