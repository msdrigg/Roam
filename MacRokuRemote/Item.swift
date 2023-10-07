//
//  Item.swift
//  MacRokuRemote
//
//  Created by Scott Driggers on 10/6/23.
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
