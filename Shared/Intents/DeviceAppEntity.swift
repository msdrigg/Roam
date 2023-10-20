import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct DeviceAppEntity: AppEntity {
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Device")

    public struct DeviceAppEntityQuery: EntityQuery {
        public init() {}
        
        @MainActor
        public func entities(for identifiers: [DeviceAppEntity.ID]) async throws -> [DeviceAppEntity] {
            let container = try getSharedModelContainer()
            let links = try container.mainContext.fetch(
                FetchDescriptor<Device>(predicate: #Predicate {
                    identifiers.contains($0.id)
                })
            )
            return links.map {$0.toAppEntity()}
        }
        
        @MainActor
        public func entities(matching string: String) async throws -> [DeviceAppEntity] {
            let container = try getSharedModelContainer()
            let links = try container.mainContext.fetch(
                FetchDescriptor<Device>(predicate: #Predicate {
                    $0.name.contains(string)
                })
            )
            return links.map {$0.toAppEntity()}
        }
        
        @MainActor
        public func suggestedEntities() async throws -> [DeviceAppEntity] {
            let container = try getSharedModelContainer()
            var descriptor = FetchDescriptor<Device>()
            descriptor.sortBy = [SortDescriptor(\Device.lastSelectedAt, order: .reverse), SortDescriptor(\Device.lastOnlineAt, order: .reverse)]
            let links = try container.mainContext.fetch(
                descriptor
            )
            return links.map {$0.toAppEntity()}
        }
    }
    public static var defaultQuery = DeviceAppEntityQuery()

    public var name: String
    public var location: String
    public var id: String
    public var mac: String?
    
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(name: String, location: String, id: String, mac: String?) {
        self.name = name
        self.location = location
        self.id = id
        self.mac = mac
    }
    
    
}

public extension Device {
    func toAppEntity() -> DeviceAppEntity {
        return DeviceAppEntity(name: self.name, location: self.location, id: self.id, mac: self.usingMac())
    }
}



public func clickButton(button: RemoteButton, device: DeviceAppEntity?) async throws {
    let modelContainer = try getSharedModelContainer()
    let deviceController = DeviceControllerActor(modelContainer: modelContainer)
    let context = ModelContext(modelContainer)
    
    guard let targetDevice = device ?? fetchSelectedDevice(context: context)?.toAppEntity() else {
        return
    }
    
    await deviceController.sendKeyToDeviceRawNotRecommended(location: targetDevice.location, key: button.apiValue, mac: targetDevice.mac)
    
    return
}
