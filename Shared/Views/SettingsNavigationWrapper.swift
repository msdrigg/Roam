import SwiftUI


struct SettingsNavigationWrapper<Content>: View where Content : View {
    @Binding var path: NavigationPath
    @ViewBuilder let content: () -> Content
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack(path: $path) {
            content()
            #if !APPCLIP
                .navigationDestination(for: SettingsDestination.self) { destination in
                    SettingsView(path: $path, destination: destination)
                }
                .navigationDestination(for: AboutDestination.self) { _ in
                    AboutView()
                }
            #endif
#if !os(watchOS)
                .navigationDestination(for: KeyboardShortcutDestination.self) { _ in
                    KeyboardShortcutPanel()
                }
#endif
            #if !APPCLIP
                .navigationDestination(for: DeviceSettingsDestination.self) { destination in
                    DeviceDetailView(device: destination.device) {
                        if path.count > 0 {
                            path.removeLast()
                        }
                    }
                }
            #endif
        }
    }
}


