import SwiftUI
import SwiftData

@main
struct RoamApp: App {
    var sharedModelContainer: ModelContainer
    init() {
        do {
            sharedModelContainer = try getSharedModelContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    

    var body: some Scene {
        WindowGroup {
            RemoteView()
        }
        #if os(macOS)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        #endif
        .modelContainer(sharedModelContainer)
        
        #if os(macOS)
        Settings {
            MacSettings()
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .modelContainer(sharedModelContainer)
        #endif

    }
}
