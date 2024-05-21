import SwiftUI

enum NavigationDestination: Hashable {
    case settingsDestination(SettingsDestination)
    case aboutDestination
    case deviceSettingsDestination(Device)
    case keyboardShortcutDestinaion
    case messageDestination
}

enum SettingsDestination {
    case global
    case debugging
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
                    case let .settingsDestination(destination):
                        #if !APPCLIP
                            SettingsView(path: $path, destination: destination)
                        #endif
                    case .aboutDestination:
                        #if !APPCLIP
                            AboutView()
                        #endif
                    case let .deviceSettingsDestination(device):
                        #if !APPCLIP
                            DeviceDetailView(device: device) {
                                if path.count > 0 {
                                    path.removeLast()
                                }
                            }
                        #endif
                    case .keyboardShortcutDestinaion:
                        #if !os(watchOS)
                            KeyboardShortcutPanel()
                        #endif
                    case .messageDestination:
                        #if !os(watchOS)
                            MessageView()
                        #endif
                    }
                }
        }
    }
}
