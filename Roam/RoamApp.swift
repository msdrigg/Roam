import OSLog
import SwiftData
import SwiftUI
#if os(macOS)
    import AppKit
#endif

@main
struct RoamApp: App {
    #if os(macOS)
        @Environment(\.openWindow) private var openWindow
    #endif

    #if os(macOS)
        @NSApplicationDelegateAdaptor(RoamAppDelegate.self) var appDelegate
    #elseif !os(watchOS)
        @UIApplicationDelegateAdaptor(RoamAppDelegate.self) var appDelegate
    #endif

    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()
    }

    var body: some Scene {
        #if os(macOS)
            Window("Roam", id: "main") {
                RemoteView()
            }
            .defaultSize(width: 400, height: 1000)
            .defaultPosition(.trailing)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .commands {
                CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                    Button(action: {
                        appDelegate.showAboutPanel()
                    }, label: {
                        Text("About Roam", comment: "Button to open the about page of the Roam app")
                    })
                }
                CommandGroup(after: .help) {
                    Button("Keyboard Shortcuts", systemImage: "keyboard") {
                        openWindow(id: "keyboard-shortcuts")
                    }
                    .customKeyboardShortcut(.keyboardShortcuts)

                    Button("Chat with the Developer", systemImage: "message") {
                        openWindow(id: "messages")
                    }
                    .customKeyboardShortcut(.chatWithDeveloper)
                }

                CommandGroup(after: .singleWindowList) {
                    Button("Keyboard Shortcuts", systemImage: "keyboard") {
                        openWindow(id: "keyboard-shortcuts")
                    }
                    .customKeyboardShortcut(.keyboardShortcuts)
                    Button("Chat with the Developer", systemImage: "message") {
                        openWindow(id: "messages")
                    }
                    .customKeyboardShortcut(.chatWithDeveloper)
                }
            }
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())
        #else
            WindowGroup {
                RemoteView()
#if os(visionOS)
                    .frame(minWidth: 400, minHeight: 950)
#endif
            }
            #if os(visionOS)
            .windowResizability(.contentMinSize)
            .defaultSize(width: 400, height: 1000)
            #endif
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())
        #endif

        #if os(macOS)
            Window(String(localized: "Messages", comment: "Window header for the messages window"), id: "messages") {
                MessageView()
                    .frame(width: 400)
            }
            .windowResizability(.contentSize)
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())

            Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
                KeyboardShortcutPanel()
            }
            .windowResizability(.contentSize)
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())
        #endif

        #if os(macOS)
            Settings {
                MacSettings()
            }
            .modelContainer(sharedModelContainer)
            .environment(\.createDataHandler, dataHandlerCreator())
            .windowToolbarStyle(.unified(showsTitle: true))
        #endif
    }
}
