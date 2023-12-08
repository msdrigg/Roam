import SwiftUI
import SwiftData

class GlobalViewSettings: ObservableObject {
    @Published var showKeyboardShortcuts: Bool

    init() {
        self.showKeyboardShortcuts = false
    }
}


@main
struct RoamApp: App {
    private var globalViewSettings: GlobalViewSettings = GlobalViewSettings()
    
    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()
        PushConfigurationManager.shared.initialize()
        MessagingManager.shared.initialize()
        MessagingManager.shared.requestNotificationPermission()
    }
    

    var body: some Scene {
        WindowGroup {
            RemoteView()
                .environmentObject(globalViewSettings)
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands {
            CommandGroup(after: .help) {
                Button("Keyboard Shortcuts", systemImage: "keyboard") {
                    globalViewSettings.showKeyboardShortcuts = !globalViewSettings.showKeyboardShortcuts
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
