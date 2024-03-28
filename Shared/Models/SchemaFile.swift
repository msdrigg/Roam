import Foundation
import SwiftData
import OSLog

enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    
    @Model
    public final class Device: Hashable {
        public static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier!, category: String(describing: Device.self)
        )
        
        @Attribute(.unique, originalName: "id") public var udn: String
        public var name: String
        public var location: String
        
        public var lastSelectedAt: Date?
        public var lastOnlineAt: Date?
        public var lastScannedAt: Date?
        public var lastSentToWatch: Date?
        public var deletedAt: Date?
        
        public var powerMode: String?
        public var networkType: String?
        public var wifiMAC: String?
        public var ethernetMAC: String?
        
        public var rtcpPort: UInt16?
        public var supportsDatagram: Bool?
        
        @Attribute(.externalStorage) public var deviceIcon: Data?
        
        public init(name: String, location: String, lastSelectedAt: Date? = nil, lastOnlineAt: Date? = nil, udn: String) {
            self.name = name
            self.lastSelectedAt = lastSelectedAt
            self.lastOnlineAt = lastOnlineAt
            self.udn = udn
            self.location = location
        }
    }
    
    @Model
    public final class AppLink: Identifiable {
        public let id: String
        public let type: String
        public let name: String
        public var lastSelected: Date? = nil
        public var deviceUid: String? = nil
        @Attribute(.externalStorage) public var icon: Data?
        
        init(id: String, type: String, name: String, icon: Data? = nil, deviceUid: String? = nil) {
            self.id = id
            self.type = type
            self.name = name
            self.icon = icon
            self.deviceUid = deviceUid
        }
    }

    static var models: [any PersistentModel.Type] {
        [Device.self, AppLink.self]
    }
}

enum RoamSchemaMigrationPlan: SchemaMigrationPlan {
    static var stages: [MigrationStage] {
        []
    }

    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }
}

