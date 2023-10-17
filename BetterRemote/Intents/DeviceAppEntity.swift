//
//  DeviceAppEntity.swift
//  BetterRemote
//
//  Created by Scott Driggers on 10/16/23.
//

import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
struct DeviceAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Device")

    struct DeviceAppEntityQuery: EntityQuery {
        @MainActor
        func entities(for identifiers: [DeviceAppEntity.ID]) async throws -> [DeviceAppEntity] {
            let container = try getSharedModelContainer()
            let links = try container.mainContext.fetch(
                FetchDescriptor<Device>(predicate: #Predicate {
                    identifiers.contains($0.id)
                })
            )
            return links.map {$0.toAppEntity()}
        }
        
        @MainActor
        func entities(matching string: String) async throws -> [DeviceAppEntity] {
            let container = try getSharedModelContainer()
            let links = try container.mainContext.fetch(
                FetchDescriptor<Device>(predicate: #Predicate {
                    $0.name.contains(string)
                })
            )
            return links.map {$0.toAppEntity()}
        }
        
        @MainActor
        func suggestedEntities() async throws -> [DeviceAppEntity] {
            let container = try getSharedModelContainer()
            var descriptor = FetchDescriptor<Device>()
            descriptor.sortBy = [SortDescriptor(\Device.lastSelectedAt, order: .reverse), SortDescriptor(\Device.lastOnlineAt, order: .reverse)]
            let links = try container.mainContext.fetch(
                descriptor
            )
            return links.map {$0.toAppEntity()}
        }
    }
    static var defaultQuery = DeviceAppEntityQuery()

    var name: String
    var location: String
    var id: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(name: String, location: String, id: String) {
        self.name = name
        self.location = location
        self.id = id
    }
    
    
}

extension Device {
    func toAppEntity() -> DeviceAppEntity {
        return DeviceAppEntity(name: self.name, location: self.location, id: self.id)
    }
}
