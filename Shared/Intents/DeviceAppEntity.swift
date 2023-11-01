import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct DeviceAppEntity: AppEntity, Equatable, Identifiable, Hashable {
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Device")

    public struct DeviceAppEntityQuery: EntityQuery {
        public init() {
        }
        
        public func entities(for identifiers: [DeviceAppEntity.ID]) async throws -> [DeviceAppEntity] {
            let deviceActor = DeviceActor(modelContainer: getSharedModelContainer())
            
            return try await deviceActor.entities(for: identifiers)
        }
        
        public func entities(matching string: String) async throws -> [DeviceAppEntity] {
            let deviceActor = DeviceActor(modelContainer: getSharedModelContainer())
            return try await deviceActor.entities(matching: string)
        }
        
        public func suggestedEntities() async throws -> [DeviceAppEntity] {
            let deviceActor = DeviceActor(modelContainer: getSharedModelContainer())
            return try await deviceActor.allDeviceEntities()
        }
    }
    public static var defaultQuery = DeviceAppEntityQuery()

    public var name: String
    public var location: String
    public var udn: String
    public var mac: String?
    public var lastSentToWatch: Date?
    public var modelId: PersistentIdentifier
    
    public var id: String {
        udn
    }
    
    public var apps: [AppLinkAppEntity]?
    
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(name: String, location: String, udn: String, mac: String?, lastSentToWatch: Date?, modelId: PersistentIdentifier, apps: [AppLinkAppEntity]?) {
        self.name = name
        self.location = location
        self.udn = udn
        self.mac = mac
        self.apps = apps
        self.lastSentToWatch = lastSentToWatch
        self.modelId = modelId
    }
    
    
}

public extension Device {
    func toAppEntity() -> DeviceAppEntity {
        return DeviceAppEntity(name: self.name, location: self.location, udn: self.udn, mac: self.usingMac(), lastSentToWatch: self.lastSentToWatch, modelId: self.persistentModelID, apps: self.appsSorted.map{$0.toAppEntity()})
    }
}

