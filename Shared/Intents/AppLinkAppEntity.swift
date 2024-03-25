import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct AppLinkAppEntity: Identifiable, Equatable, Hashable, Encodable, Sendable {
    var name: String
    public var id: String
    public var type: String
    public var modelId: PersistentIdentifier
    public var icon: Data?

    init(name: String, id: String, type: String, modelId: PersistentIdentifier, icon: Data? = nil) {
        self.name = name
        self.id = id
        self.type = type
        self.modelId = modelId
        self.icon = icon
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, name
    }
}

#if !os(tvOS)
extension AppLinkAppEntity: AppEntity {
    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "TV App")
    public static var defaultQuery = AppLinkAppEntityQuery()

    public struct AppLinkAppEntityQuery: EntityQuery {
        @IntentParameterDependency<LaunchAppIntent>(\.$device) var launchAppIntent

        public init() {}

        public func entities(for identifiers: [AppLinkAppEntity.ID]) async throws -> [AppLinkAppEntity] {
            let appLinkActor = AppLinkActor(modelContainer: getSharedModelContainer())
            return try await appLinkActor.entities(for: identifiers, deviceUid: launchAppIntent?.device.udn)
        }

        func entities(matching string: String) async throws -> [AppLinkAppEntity] {
            let appLinkActor = AppLinkActor(modelContainer: getSharedModelContainer())
            return try await appLinkActor.entities(matching: string, deviceUid: launchAppIntent?.device.udn)
        }

        public func suggestedEntities() async throws -> [AppLinkAppEntity] {
            let appLinkActor = AppLinkActor(modelContainer: getSharedModelContainer())
            return try await appLinkActor.entities(deviceUid: launchAppIntent?.device.udn)
        }
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}
#endif


public extension AppLink {
    func toAppEntity() -> AppLinkAppEntity {
        return AppLinkAppEntity(name: self.name, id: self.id, type: self.type, modelId: self.persistentModelID)
    }
    
    func toAppEntityWithIcon() -> AppLinkAppEntity {
        return AppLinkAppEntity(name: self.name, id: self.id, type: self.type, modelId: self.persistentModelID, icon: self.icon)
    }
}

public func launchApp(app: AppLinkAppEntity, device: DeviceAppEntity?) async throws {
    let modelContainer = getSharedModelContainer()
    
    var targetDevice = device
    if targetDevice == nil {
        targetDevice = await fetchSelectedDevice(modelContainer: modelContainer)
    }
    
    if let targetDevice = targetDevice {
        do {
            try await openApp(location: targetDevice.location, app: app.id)
        } catch {
            throw ApiError.deviceNotConnectable
        }
    } else {
        throw ApiError.noSavedDevices
    }
}

enum ApiError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noSavedDevices
    case deviceNotConnectable

    var localizedStringResource: LocalizedStringResource {
        switch self {
            case .noSavedDevices: return "No saved devices"
            case .deviceNotConnectable: return "Couldn't connect to the device"
        }
    }
}

