import Foundation
import AppIntents
import SwiftData

@available(iOS 16.0, macOS 13.0, watchOS 9.0, tvOS 16.0, *)
public struct AppLinkAppEntity: Identifiable, Equatable, Hashable, Encodable, Sendable {
    var name: String
    public var id: String
    public var type: String
    public var icon: Data?
    public var modelId: PersistentIdentifier

    init(name: String, id: String, type: String, icon: Data?, modelId: PersistentIdentifier) {
        self.name = name
        self.id = id
        self.type = type
        self.icon = icon
        self.modelId = modelId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        
        let iconHash = icon?.hashValue
        try container.encodeIfPresent(iconHash, forKey: .iconHash)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, name, iconHash
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
            if let apps = launchAppIntent?.device.apps {
                return apps
            }
            let appLinkActor = AppLinkActor(modelContainer: getSharedModelContainer())
            return try await appLinkActor.entities(for: identifiers)
        }

        func entities(matching string: String) async throws -> [AppLinkAppEntity] {
            if let apps = launchAppIntent?.device.apps {
                return apps.filter{$0.name.contains(string)}
            }
            let appLinkActor = AppLinkActor(modelContainer: getSharedModelContainer())
            return try await appLinkActor.entities(matching: string)
        }

        public func suggestedEntities() async throws -> [AppLinkAppEntity] {
            if let apps = launchAppIntent?.device.apps {
                return apps
            }
            let appLinkActor = AppLinkActor(modelContainer: getSharedModelContainer())
            return try await appLinkActor.suggestedEntities()
        }
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}
#endif


public extension AppLink {
    func toAppEntity() -> AppLinkAppEntity {
        return AppLinkAppEntity(name: self.name, id: self.id, type: self.type, icon: self.icon, modelId: self.persistentModelID)
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

