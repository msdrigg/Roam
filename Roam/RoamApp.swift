import SwiftUI
import SwiftData

@main
struct RoamApp: App {
    @State var showKeyboardShortcuts: Bool = false
    
    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()
    }
    

    var body: some Scene {
        WindowGroup {
            RemoteView(showKeyboardShortcuts: $showKeyboardShortcuts)
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .help) {
                Button("Keyboard Shortcuts", systemImage: "keyboard") {
                    showKeyboardShortcuts = !showKeyboardShortcuts
                }
                .keyboardShortcut("k")
                
            }
        }
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
