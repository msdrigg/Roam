import WidgetKit
import SwiftUI

@main
struct RoamWidgetsApp: WidgetBundle {
    var body: some Widget {
#if !os(watchOS)
       SmallDpadWidget()
       SmallMediaWidget()
       SmallAppWidget()
       MediumRemoteWidget()
#endif
#if !os(macOS)
       SmallVolumeWidget()
       SmallerAppWidget()
#endif
   }
}
