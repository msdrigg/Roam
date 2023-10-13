import Foundation
import SwiftData


@Model
final class Device: Identifiable {
    public let id: String
    public var name: String
    public var location: String
    
    public var lastSelectedAt: Date?
    public var lastOnlineAt: Date?
    public var lastScannedAt: Date?
    
    // DisplayOff or PowerOn or Suspend
    public var powerMode: String?
    public var networkType: String?
    public var wifiMAC: String?
    public var ethernetMAC: String?
    
    public var rtcpPort: UInt16?
    public var supportsDatagram: Bool?
    
    @Attribute(.externalStorage) public var deviceIcon: Data?
    // Associate 0..n Apps with Device
    @Relationship(deleteRule: .nullify)
    public var apps: [AppLink]? = []
    
    var appsSorted: [AppLink]? {
       apps?.sorted(by: {
            switch ($0.type, $1.type) {
            case ("appl", "appl"): return Int($0.id) ?? 99999999 < Int($1.id) ?? 99999999
            case ("tvin", "tvin"): return $0.name < $1.name
            case ("appl", _): return true
            case (_, "appl"): return false
            case ("tvin", _): return false
            case (_, "tvin"): return true
            default: return false
            }
        })
    }
    
    public init(name: String, location: String, lastSelectedAt: Date? = nil, lastOnlineAt: Date? = nil, id: String, apps: [AppLink] = []) {
        self.name = name
        self.lastSelectedAt = lastSelectedAt
        self.lastOnlineAt = lastOnlineAt
        self.id = id
        self.location = location
    
        self.apps = apps
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
    let apps = getTestingAppLinks()
    
    return [
        Device(name: "Living Room TV", location: "192.168.0.1", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0), id: "TD1", apps: apps),
        Device(name: "2nd Living Room", location: "192.168.0.2", lastSelectedAt: Date(timeIntervalSince1970: 1696767580.0 - 24 * 60 * 60), id: "TD2", apps: [])
    ]
}

let devicePreviewContainer: ModelContainer = {
    do {
        let container = try ModelContainer(for: Device.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        
        Task { @MainActor in
            let context = container.mainContext
            
            let models = getTestingDevices()
            for model in models {
                context.insert(model)
            }
        }
        return container
    } catch {
        fatalError("Failed to create container with error: \(error.localizedDescription)")
    }
}()
