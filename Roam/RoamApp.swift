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
            .modelContainer(sharedModelContainer)
            .defaultSize(width: 400, height: 1000)
            .defaultPosition(.trailing)
            .windowToolbarStyle(.unifiedCompact(showsTitle: false))
            .commands {
                CommandGroup(replacing: CommandGroupPlacement.appInfo) {
                    Button(action: {
                        appDelegate.showAboutPanel()
                    }, label: {
                        Text("About Roam")
                    })
                }
                CommandGroup(after: .help) {
                    Button("Keyboard Shortcuts", systemImage: "keyboard") {
                        #if os(macOS)
                            openWindow(id: "keyboard-shortcuts")
                        #else
                            navigationPath.append(NavigationDestination.KeyboardShortcutDestinaion)
                        #endif
                    }
                    .keyboardShortcut("k")

                    Button("Chat with Developer", systemImage: "message") {
                        #if os(macOS)
                            openWindow(id: "messages")
                        #else
                            navigationPath.append(NavigationDestination.MessageDestination)
                        #endif
                    }
                    .keyboardShortcut("j")
                }

                CommandGroup(after: .singleWindowList) {
                    Button("Keyboard Shortcuts", systemImage: "keyboard") {
                        #if os(macOS)
                            openWindow(id: "keyboard-shortcuts")
                        #else
                            navigationPath.append(NavigationDestination.KeyboardShortcutDestinaion)
                        #endif
                    }
                    .keyboardShortcut("k")

                    Button("Chat with Developer", systemImage: "message") {
                        #if os(macOS)
                            openWindow(id: "messages")
                        #else
                            navigationPath.append(NavigationDestination.MessageDestination)
                        #endif
                    }
                    .keyboardShortcut("j")
                }
            }
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
        #endif

        #if os(macOS)
            Window("Messages", id: "messages") {
                MessageView()
                    .frame(width: 400)
            }
            .windowResizability(.contentSize)
            .modelContainer(sharedModelContainer)

            Window("Keyboard Shortcuts", id: "keyboard-shortcuts") {
                KeyboardShortcutPanel()
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
