#if os(iOS)
import TipKit
import SwiftUI

/// Popover tip anchored to the pasted-URL offer banner on iOS. The banner is
/// driven by pasteboard *pattern* detection (which can't see the URL itself,
/// to avoid the system paste notice), so the tip explains that the offer also
/// appears for links Roam can't play, and that it can be turned off in
/// Settings.
struct PastedUrlOfferTip: Tip {
    var title: Text = Text("Open copied videos on your TV")
    var image: Image? = Image(systemName: "doc.on.clipboard")
    // swiftlint:disable:next line_length
    var message: Text? = Text("Copy a video link (YouTube, Netflix, Hulu, and more) and Roam will offer to play it on your TV. This appears whenever any web link is copied — even ones Roam can't play. You can turn it off in Settings.")

    var options: [any TipOption] {
        MaxDisplayCount(3)
    }
}
#endif
