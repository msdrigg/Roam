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
            // VisionOS doesn't respect object content, so we need to set explicit sizing bounds
#if os(visionOS)
                .frame(minWidth: 400, minHeight: 950)
#endif
        }
        #if os(visionOS) || os(macOS)
        .defaultSize(width: 400, height: 1000)
        .windowResizability(.contentSize)
        #endif
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultPosition(.trailing)
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
