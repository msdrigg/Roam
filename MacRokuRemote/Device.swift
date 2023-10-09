//
//  AppLink.swift
//  MacRokuRemote
//
//  Created by Scott Driggers on 10/7/23.
//

import Foundation
import SwiftData

@Model
final class Device: Identifiable {
    public let id: String
    public var name: String
    public var location: String
    public var lastSelectedAt: Date?
    public var lastOnlineAt: Date?
    
    public init(name: String, location: String, id: String, lastSelectedAt: Date? = nil, lastOnlineAt: Date? = nil) {
        self.name = name
        self.lastSelectedAt = lastSelectedAt
        self.lastOnlineAt = lastOnlineAt
        self.location = location
        self.id = id
    }
    
    public func isOnline() -> Bool {
        guard let lastOnlineAt = self.lastOnlineAt else {
             return false
         }
        return Date().timeIntervalSince(lastOnlineAt) < 60
    }
}

func getTestingDevices() -> [Device] {
    [
        Device(name: "Living Room TV", location: "192.168.0.1", id: "1", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0)),
        Device(name: "2nd Living Room", location: "192.168.0.2", id: "2", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0 - 24 * 60 * 60))
    ]
}
