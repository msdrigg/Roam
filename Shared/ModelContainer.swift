import SwiftData

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
    let schema = Schema([
        AppLink.self,
        Device.self,
    ])
    
    let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, groupContainer: .identifier("group.com.msdrigg.roam"))
    
    return try ModelContainer(for: schema, configurations: [modelConfiguration])
}
