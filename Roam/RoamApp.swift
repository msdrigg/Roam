import SwiftUI
import SwiftData

@main
struct RoamApp: App {
    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()
    }
    

    var body: some Scene {
        WindowGroup {
            RemoteView()
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        #endif
        
        #if os(macOS)
        Settings {
            MacSettings()
        }
        .modelContainer(sharedModelContainer)
        .windowToolbarStyle(.unified(showsTitle: true))
        #endif

    }
}
