//
//  WidgetHelpers.swift
//  BetterRemote
//
//  Created by Scott Driggers on 10/17/23.
//

import Foundation
import SwiftData
import AppIntents
import WidgetKit

struct DeviceChoiceTimelineEntity: TimelineEntry {
    var date: Date
    var device: DeviceAppEntity?
}

struct RemoteControlProvider: AppIntentTimelineProvider {
    typealias Intent = DeviceChoiceIntent
    typealias Entry = DeviceChoiceTimelineEntity
    
    private let modelContainer: ModelContainer
    
    init() {
        do {
            modelContainer = try getSharedModelContainer()
        } catch {
            fatalError("Failed to create the model container: \(error)")
        }
    }
    
    @MainActor
    func snapshot(for configuration: DeviceChoiceIntent, in context: Context) async -> DeviceChoiceTimelineEntity {
        let entry = DeviceChoiceTimelineEntity(date: Date(), device: configuration.useDefaultDevice ? nil : configuration.device ?? fetchSelectedDevice(context: modelContainer.mainContext)?.toAppEntity())
        return entry
    }
    
    @MainActor
    func timeline(for configuration: DeviceChoiceIntent, in context: Context) async -> Timeline<DeviceChoiceTimelineEntity> {
        let currentDate = Date()
        let entry = DeviceChoiceTimelineEntity(date: currentDate, device: configuration.useDefaultDevice ? nil : configuration.device ?? fetchSelectedDevice(context: modelContainer.mainContext)?.toAppEntity())
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        return timeline
    }
    
    func placeholder(in context: Context) -> DeviceChoiceTimelineEntity {
        DeviceChoiceTimelineEntity(date: Date(), device: nil)
    }
}
