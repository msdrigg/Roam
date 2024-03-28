//
//  Item.swift
//  RoamClip
//
//  Created by Scott Driggers on 3/27/24.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
