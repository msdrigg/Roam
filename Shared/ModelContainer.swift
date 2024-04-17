import SwiftData


public let APP_GROUP = "group.com.msdrigg.roam.models"

public class GlobalModelContainer {
    static let sharedModelContainer = demandSharedModelContainer()
}

public func getSharedModelContainer() -> ModelContainer {
    return GlobalModelContainer.sharedModelContainer
}

private func demandSharedModelContainer() -> ModelContainer {
    do {
        return try _getSharedModelContainer()
    } catch {
        fatalError("Error getting shared model container \(error))")
    }
}

private func _getSharedModelContainer() throws -> ModelContainer {
    let schema = Schema(
        versionedSchema: SchemaV1.self
    )
    
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .identifier(APP_GROUP))
    
    return try ModelContainer(for: schema, migrationPlan: RoamSchemaMigrationPlan.self, configurations: [modelConfiguration])
}
