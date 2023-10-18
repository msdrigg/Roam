//
//  BetterRemoteWidgetsBundle.swift
//  BetterRemoteWidgets
//
//  Created by Scott Driggers on 10/18/23.
//

import WidgetKit
import SwiftUI

@main
struct BetterRemoteWidgetsBundle: WidgetBundle {
   var body: some Widget {
       SmallRemoteWidget()
       MediumRemoteWidget()
   }
}
