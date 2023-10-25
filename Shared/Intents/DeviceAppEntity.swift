import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct DeviceAppEntity: AppEntity {
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Device")

    public struct DeviceAppEntityQuery: EntityQuery {
        public init() {
        }
        
        public func entities(for identifiers: [DeviceAppEntity.ID]) async throws -> [DeviceAppEntity] {
            let deviceActor = try DeviceActor(modelContainer: getSharedModelContainer())
            
            return try await deviceActor.entities(for: identifiers)
        }
        
        public func entities(matching string: String) async throws -> [DeviceAppEntity] {
            let deviceActor = try DeviceActor(modelContainer: getSharedModelContainer())
            return try await deviceActor.entities(matching: string)
        }
        
        public func suggestedEntities() async throws -> [DeviceAppEntity] {
            let deviceActor = try DeviceActor(modelContainer: getSharedModelContainer())
            return try await deviceActor.suggestedEntities()
        }
    }
    public static var defaultQuery = DeviceAppEntityQuery()

    public var name: String
    public var location: String
    public var id: String
    public var mac: String?
    
    public var apps: [AppLinkAppEntity]?
    
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(name: String, location: String, id: String, mac: String?, apps: [AppLinkAppEntity]?) {
        self.name = name
        self.location = location
        self.id = id
        self.mac = mac
        self.apps = apps
    }
    
    
}

public extension Device {
    func toAppEntity() -> DeviceAppEntity {
        return DeviceAppEntity(name: self.name, location: self.location, id: self.id, mac: self.usingMac(), apps: self.appsSorted?.map{$0.toAppEntity()})
    }
}

public func clickButton(button: RemoteButton, device: DeviceAppEntity?) async throws {
    let modelContainer = try getSharedModelContainer()
    let deviceController = DeviceControllerActor()
    
    var targetDevice = device
    if targetDevice == nil {
        targetDevice = await fetchSelectedDevice(modelContainer: modelContainer)
    }
    
    if let deviceKey = button.apiValue, let targetDevice = targetDevice {
        await deviceController.sendKeyToDeviceRawNotRecommended(location: targetDevice.location, key: deviceKey, mac: targetDevice.mac)
    }
    
    return
}
