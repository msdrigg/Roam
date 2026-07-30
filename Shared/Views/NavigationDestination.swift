import SwiftUI

enum NavigationDestination: Hashable {
    case settingsDestination(SettingsDestination)
    case aboutDestination
    case deviceSettingsDestination(String)
    case keyboardShortcutDestinaion
    case messageDestination
#if os(iOS)
    case appIconDestination
#endif
}

enum SettingsDestination {
    case global
    case debugging
}
