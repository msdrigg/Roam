import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
struct AppLinkAppEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "TV App")

    struct AppLinkAppEntityQuery: EntityQuery {
//        @IntentParameterDependency<LaunchAppIntent>(\.$device) var launchAppIntent
        
        @MainActor
        func entities(for identifiers: [AppLinkAppEntity.ID]) async throws -> [AppLinkAppEntity] {
//            let device = launchAppIntent?.device

            let container = try getSharedModelContainer()
            let links = try container.mainContext.fetch(
                FetchDescriptor<AppLink>(predicate: #Predicate { appLink in
                    identifiers.contains(appLink.id)
                })
            )
            return links.map {$0.toAppEntity()}
        }
        
        @MainActor
        func entities(matching string: String) async throws -> [AppLinkAppEntity] {
//            let device = launchAppIntent?.device
   
            let container = try getSharedModelContainer()
            let links = try container.mainContext.fetch(
                FetchDescriptor<AppLink>(predicate: #Predicate { appLink in
                    appLink.name.contains(string)
                })
            )
            return links.map {$0.toAppEntity()}
        }
        
        @MainActor
        func suggestedEntities() async throws -> [AppLinkAppEntity] {
            let container = try getSharedModelContainer()
            let descriptor = FetchDescriptor<AppLink>()
            let links = try container.mainContext.fetch(
                descriptor
            )
            return links.map {$0.toAppEntity()}
        }
    }
    static var defaultQuery = AppLinkAppEntityQuery()

    var name: String
    var id: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    init(name: String, id: String) {
        self.name = name
        self.id = id
    }
}


extension AppLink {
    func toAppEntity() -> AppLinkAppEntity {
        return AppLinkAppEntity(name: self.name, id: self.id)
    }
}
