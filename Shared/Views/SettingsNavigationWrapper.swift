import SwiftUI

enum NavigationDestination: Hashable {
    case SettingsDestination(SettingsDestination)
    case AboutDestination
    case DeviceSettingsDestination(Device)
    case KeyboardShortcutDestinaion
    case MessageDestination
}

enum SettingsDestination {
    case Global
    case Debugging
}

struct SettingsNavigationWrapper<Content>: View where Content: View {
    @Binding var path: [NavigationDestination]
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            content()
                .navigationDestination(for: NavigationDestination.self) { globalDestination in
                    switch globalDestination {
                    case let .SettingsDestination(destination):
                        #if !APPCLIP
                            SettingsView(path: $path, destination: destination)
                        #endif
                    case .AboutDestination:
                        #if !APPCLIP
                            AboutView()
                        #endif
                    case let .DeviceSettingsDestination(device):
                        let _ = print("Getting nav to settings dest")
                        #if !APPCLIP
                            DeviceDetailView(device: device) {
                                if path.count > 0 {
                                    path.removeLast()
                                }
                            }
                        #endif
                    case .KeyboardShortcutDestinaion:
                        #if !os(watchOS)
                            KeyboardShortcutPanel()
                        #endif
                    case .MessageDestination:
                        #if !os(watchOS)
                            MessageView()
                        #endif
                    }
                }
        }
    }
}
