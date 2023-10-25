import WidgetKit
import SwiftUI

@main
struct RoamWidgetsBundle: WidgetBundle {
   var body: some Widget {
       SmallDpadWidget()
       SmallMediaWidget()
       SmallAppWidget()
       MediumRemoteWidget()
   }
}
