import AppIntents
import Foundation
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct DeviceAppEntity: AppEntity, Equatable, Identifiable, Hashable, Encodable {
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Device")

    public struct DeviceAppEntityQuery: EntityQuery {
        public init() {}

        public func entities(for identifiers: [DeviceAppEntity.ID]) async throws -> [DeviceAppEntity] {
            let deviceActor = DataHandler(modelContainer: getSharedModelContainer())

            return try await deviceActor.deviceEntities(for: identifiers)
        }

        public func entities(matching string: String) async throws -> [DeviceAppEntity] {
            let deviceActor = DataHandler(modelContainer: getSharedModelContainer())
            return try await deviceActor.deviceEntities(matching: string)
        }

        public func suggestedEntities() async throws -> [DeviceAppEntity] {
            let deviceActor = DataHandler(modelContainer: getSharedModelContainer())
            return try await deviceActor.allDeviceEntities()
        }
    }

    public static var defaultQuery = DeviceAppEntityQuery()

    public var name: String
    public var location: String
    public var udn: String
    public var lastSentToWatch: Date?
    public var modelId: PersistentIdentifier

    public var lastSelectedAt: Date?
    public var lastOnlineAt: Date?
    public var lastScannedAt: Date?
    public var deletedAt: Date?

    // DisplayOff or PowerOn or Suspend
    public var powerMode: String?
    public var networkType: String?
    public var wifiMAC: String?
    public var ethernetMAC: String?

    public var rtcpPort: UInt16?
    public var supportsDatagram: Bool?

    public var id: String {
        udn
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    func usingMac() -> String? {
        if networkType == "ethernet" {
            ethernetMAC
        } else {
            wifiMAC
        }
    }

    init(device: Device) {
        name = device.name
        location = device.location
        udn = device.udn
        wifiMAC = device.wifiMAC
        ethernetMAC = device.ethernetMAC
        lastSentToWatch = device.lastSentToWatch
        modelId = device.persistentModelID
        lastSelectedAt = device.lastSelectedAt
        lastOnlineAt = device.lastOnlineAt
        lastScannedAt = device.lastScannedAt
        deletedAt = device.deletedAt
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(udn, forKey: .udn)
        try container.encode(name, forKey: .name)
        try container.encode(location, forKey: .location)

        try container.encodeIfPresent(lastSelectedAt, forKey: .lastSelectedAt)
        try container.encodeIfPresent(lastOnlineAt, forKey: .lastOnlineAt)
        try container.encodeIfPresent(lastScannedAt, forKey: .lastScannedAt)
        try container.encodeIfPresent(lastSentToWatch, forKey: .lastSentToWatch)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)

        try container.encodeIfPresent(powerMode, forKey: .powerMode)
        try container.encodeIfPresent(networkType, forKey: .networkType)
        try container.encodeIfPresent(wifiMAC, forKey: .wifiMAC)
        try container.encodeIfPresent(ethernetMAC, forKey: .ethernetMAC)

        try container.encodeIfPresent(rtcpPort, forKey: .rtcpPort)
        try container.encodeIfPresent(supportsDatagram, forKey: .supportsDatagram)
    }

    private enum CodingKeys: String, CodingKey {
        case udn
        case name
        case location
        case lastSelectedAt
        case lastOnlineAt
        case lastScannedAt
        case lastSentToWatch
        case deletedAt
        case powerMode
        case networkType
        case wifiMAC
        case ethernetMAC
        case rtcpPort
        case supportsDatagram
    }
}

public extension Device {
    func toAppEntity() -> DeviceAppEntity {
        DeviceAppEntity(device: self)
    }
}
