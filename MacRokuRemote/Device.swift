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
    public let id: UUID
    public var name: String
    public var host: String
    public var lastSelectedAt: Date?
    public var lastOnlineAt: Date?
    
    public init(name: String, host: String, lastSelectedAt: Date? = nil, lastOnlineAt: Date? = nil, id: UUID? = nil) {
        self.name = name
        self.lastSelectedAt = lastSelectedAt
        self.lastOnlineAt = lastOnlineAt
        self.id = id ?? UUID()
        self.host = host
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
        Device(name: "Living Room TV", host: "192.168.0.1", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0), id: UUID(uuidString: "118ccc25-e3fa-4d04-9b25-887b5d7e2f93")),
        Device(name: "2nd Living Room", host: "192.168.0.2", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0 - 24 * 60 * 60), id: UUID(uuidString: "118ccc25-e3fa-4d04-9b25-887b5d7e2f94"))
    ]
}
