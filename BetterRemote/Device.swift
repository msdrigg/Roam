import Foundation
import SwiftData


@Model
final class Device: Identifiable {
    public let id: String
    public var name: String
    public var location: String
    public var lastSelectedAt: Date?
    public var lastOnlineAt: Date?
    // DisplayOff or PowerOn or Suspend
    public var powerMode: String?
    // ethernet or ??
    public var networkType: String?
    public var wifiMAC: String?
    public var ethernetMAC: String?
    
    public init(name: String, location: String, lastSelectedAt: Date? = nil, lastOnlineAt: Date? = nil, id: String) {
        self.name = name
        self.lastSelectedAt = lastSelectedAt
        self.lastOnlineAt = lastOnlineAt
        self.id = id
        self.location = location
    }
    
    public func powerModeOn() -> Bool {
        return self.powerMode == "PowerOn"
    }
    
    public func isOnline() -> Bool {
        guard let lastOnlineAt = self.lastOnlineAt else {
             return false
         }
        return Date().timeIntervalSince(lastOnlineAt) < 60
    }
    
    
    func usingMac() -> String? {
        if networkType == "ethernet" {
            return ethernetMAC
        } else {
            return wifiMAC
        }
    }
}

func getTestingDevices() -> [Device] {
    [
        Device(name: "Living Room TV", location: "192.168.0.1", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0), id: "TD1"),
        Device(name: "2nd Living Room", location: "192.168.0.2", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0 - 24 * 60 * 60), id: "TD2")
    ]
}
