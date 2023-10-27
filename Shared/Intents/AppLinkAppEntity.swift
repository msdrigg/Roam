import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct AppLinkAppEntity: AppEntity, Identifiable, Equatable {
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "TV App")

    public struct AppLinkAppEntityQuery: EntityQuery {
//        @IntentParameterDependency<LaunchAppIntent>(\.$device) var launchAppIntent
        
        public init() {}
        
        public func entities(for identifiers: [AppLinkAppEntity.ID]) async throws -> [AppLinkAppEntity] {
//            let device = launchAppIntent?.device
            let appLinkActor = try AppLinkActor(modelContainer: getSharedModelContainer())
            return try await appLinkActor.entities(for: identifiers)
        }
        
        func entities(matching string: String) async throws -> [AppLinkAppEntity] {
//            let device = launchAppIntent?.device
   
            let appLinkActor = try AppLinkActor(modelContainer: getSharedModelContainer())
            return try await appLinkActor.entities(matching: string)
        }
        
        public func suggestedEntities() async throws -> [AppLinkAppEntity] {
            let appLinkActor = try AppLinkActor(modelContainer: getSharedModelContainer())
            return try await appLinkActor.suggestedEntities()
        }
    }
    public static var defaultQuery = AppLinkAppEntityQuery()

    var name: String
    public var id: String
    public var type: String
    public var icon: Data?
    
    public  var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(name: String, id: String, type: String, icon: Data?) {
        self.name = name
        self.id = id
        self.type = type
        self.icon = icon
    }
}


public extension AppLink {
    func toAppEntity() -> AppLinkAppEntity {
        return AppLinkAppEntity(name: self.name, id: self.id, type: self.type, icon: self.icon)
    }
}

public func launchApp(app: AppLinkAppEntity, device: DeviceAppEntity?) async throws {
    let modelContainer = try getSharedModelContainer()
    
    var targetDevice = device
    if targetDevice == nil {
        targetDevice = await fetchSelectedDevice(modelContainer: modelContainer)
    }
    
    if let targetDevice = targetDevice {
        try await openApp(location: targetDevice.location, app: app.id)
    }
    
    return
}
