import SwiftUI
import SwiftData
import OSLog
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
    @NSApplicationDelegateAdaptor(RoamAppDelegate.self) var appDelegate
    #endif

    
    var sharedModelContainer: ModelContainer
    init() {
        sharedModelContainer = getSharedModelContainer()
    }
    
    var body: some Scene {
        Window("Roam", id: "main") {
            RemoteView()
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
                    #if os(macOS)
                    openWindow(id: "keyboard-shortcuts")
                    #else
                    navigationPath.append(KeyboardShortcutDestination.Global)
                    #endif
                }
                .keyboardShortcut("k")
                
                
                Button("Chat with Developer", systemImage: "message") {
                    #if os(macOS)
                    openWindow(id: "messages")
                    #else
                    navigationPath.append(MessagingDestination.Global)
                    #endif
                }
                .keyboardShortcut("j")
            }
            
            CommandGroup(after: .singleWindowList) {
                Button("Keyboard Shortcuts", systemImage: "keyboard") {
                    #if os(macOS)
                    openWindow(id: "keyboard-shortcuts")
                    #else
                    navigationPath.append(KeyboardShortcutDestination.Global)
                    #endif
                }
                .keyboardShortcut("k")
                
                
                Button("Chat with Developer", systemImage: "message") {
                    #if os(macOS)
                    openWindow(id: "messages")
                    #else
                    navigationPath.append(MessagingDestination.Global)
                    #endif
                }
                .keyboardShortcut("j")
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
