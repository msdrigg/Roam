#if os(macOS)
import TipKit
import SwiftUI

struct GlobalKeyboardShortcutTip: Tip {
    var title: Text = Text("Want a keyboard shortcut that works everywhere?")
    // swiftlint:disable:next line_length
    var message: Text? = Text("Open the \"Shortcuts\" application, and choose one of the Roam shortcuts. Then add a [keyboard shortcut](https://support.apple.com/guide/shortcuts-mac/launch-a-shortcut-from-another-app-apd163eb9f95/7.0/mac/14.0#apd94a0e7c32) to it")

    static let viewedKeyboardShortcuts: Event = Event(id: "viewedKeyboardShortcuts")

    var rules: [Rule] {
        #Rule(Self.viewedKeyboardShortcuts) {
            $0.donations.count <= 3
        }
    }

    var actions: [Action] {
        Action(id: "open-shortcuts", title: "Open shortcuts")
    }
}

/// Inline tip shown at the bottom of the macOS remote once the app has been
/// used a bit. Points out keyboard shortcuts (⌘K) and direct keyboard text
/// entry, which is separate from the per-button shortcuts.
struct KeyboardShortcutsRemoteTip: Tip {
    /// Donated on every remote button / key press on macOS so the remote tips
    /// only surface after the user has actually been using the app.
    static let usedRemote: Event = Event(id: "usedRemoteOnMac")

    var title: Text = Text("Your keyboard controls the TV")
    var image: Image? = Image(systemName: "keyboard")
    // swiftlint:disable:next line_length
    var message: Text? = Text("Roam has a keyboard shortcut for every remote button - press ⌘K to see and change them all. You can also type to enter text on the TV and use the arrow keys to navigate, separate from the button shortcuts.")

    var rules: [Rule] {
        #Rule(Self.usedRemote) {
            $0.donations.count >= 10
        }
    }
}

/// Inline tip shown at the bottom of the macOS remote after the keyboard tip
/// has been dismissed, explaining that pasting a link opens and plays it.
struct PasteToPlayTip: Tip {
    /// Set to true once `KeyboardShortcutsRemoteTip` has been dismissed so this
    /// tip never overlaps with it and only appears afterwards.
    @Parameter static var keyboardTipDismissed: Bool = false

    var title: Text = Text("Paste a link to start watching")
    var image: Image? = Image(systemName: "doc.on.clipboard")
    var message: Text? = Text("Copy a video link, click the Roam window, and press ⌘V. Roam opens the right app on your TV and plays it - works with YouTube, Amazon Prime, Netflix, and many others.")

    var rules: [Rule] {
        #Rule(KeyboardShortcutsRemoteTip.usedRemote) {
            $0.donations.count >= 40
        }
        #Rule(Self.$keyboardTipDismissed) {
            $0 == true
        }
    }
}
#endif
