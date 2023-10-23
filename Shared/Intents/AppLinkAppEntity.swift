import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct AppLinkAppEntity: AppEntity {
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
    
    public  var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(name: String, id: String, type: String) {
        self.name = name
        self.id = id
        self.type = type
    }
}


public extension AppLink {
    func toAppEntity() -> AppLinkAppEntity {
        return AppLinkAppEntity(name: self.name, id: self.id, type: self.type)
    }
}
