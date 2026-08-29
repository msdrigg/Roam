import TipKit
import SwiftUI

/// Shown the first time volume is used on a Roku that reports `is-tv=false` -
/// a stick, an Express, or any other player without speakers of its own.
///
/// Those devices forward `VolumeUp`/`VolumeDown`/`Mute` to the TV or receiver
/// over HDMI-CEC, which works on plenty of setups but only once CEC is switched
/// on at the TV. Every vendor gives it a different name, which is what makes
/// this worth a hint.
///
/// Advisory only. The keypress is always sent. An earlier version suppressed it
/// outright on these devices, which broke every working CEC setup.
struct VolumeOverHDMITip: Tip {
    static let attemptedVolume: Event = Event(id: "attemptedVolumeOnHDMI")

    var title: Text {
        Text("Volume goes through your TV")
    }

    var image: Image? {
        Image(systemName: "speaker.wave.2")
    }

    var message: Text? {
        Text(
            // swiftlint:disable:next line_length
            "This Roku has no speakers of its own, so Roam sends volume to your TV or receiver over HDMI-CEC. If nothing happens, turn CEC on in your TV's settings - it's usually under a brand name like Anynet+, Bravia Sync, SimpLink, or VIERA Link."
        )
    }

    var rules: [Rule] {
        #Rule(Self.attemptedVolume) {
            $0.donations.count > 0
        }
    }
}
