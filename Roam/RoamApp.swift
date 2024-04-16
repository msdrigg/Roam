import SwiftUI
import SwiftData
import OSLog

@main
struct RoamApp: App {
    @State var showKeyboardShortcuts: Bool = false
    #if os(macOS)
    @NSApplicationDelegateAdaptor(RoamAppDelegate.self) var appDelegate
    #endif

    
    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()
    }
    
    var body: some Scene {
        WindowGroup {
            RemoteView(showKeyboardShortcuts: $showKeyboardShortcuts)
#if os(visionOS)
                .frame(minWidth: 400, minHeight: 950)
#endif

        }
        #if os(visionOS) || os(macOS)
        .defaultSize(width: 400, height: 1000)
        .windowResizability(.contentMinSize)
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
        .commands {
            CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                Button(action: {
                    appDelegate.showAboutPanel()
                }) {
                    Text("About Roam")
                }
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
