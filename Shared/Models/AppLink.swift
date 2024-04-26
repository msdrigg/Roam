import Foundation
import os
import SwiftData

typealias AppLink = SchemaV1.AppLink

extension AppLink: Decodable {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let type = try container.decode(String.self, forKey: .type)

        let singleValueContainer = try decoder.singleValueContainer()
        let name = try singleValueContainer.decode(String.self)

        self.init(id: id, type: type, name: name)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        var svc = encoder.singleValueContainer()

        try svc.encode(name)
    }

    enum CodingKeys: String, CodingKey {
        case id, type
    }
}

// Models shouldn't be sendable
@available(*, unavailable)
extension AppLink: Sendable {}

@ModelActor
actor AppLinkActor {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AppLinkActor.self)
    )

    public func allEntities() throws -> [AppLinkAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<AppLink>(predicate: #Predicate { _ in
                true
            })
        )
        return links.map { $0.toAppEntityWithIcon() }
    }

    public func entities(for identifiers: [AppLinkAppEntity.ID], deviceUid: String?) throws -> [AppLinkAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<AppLink>(predicate: #Predicate { appLink in
                identifiers.contains(appLink.id) && (deviceUid == nil || appLink.deviceUid == deviceUid)
            })
        )
        return links.map { $0.toAppEntityWithIcon() }
    }

    public func entities(matching string: String, deviceUid: String?) throws -> [AppLinkAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<AppLink>(predicate: #Predicate<AppLink> { appLink in
                appLink.name.contains(string) && (deviceUid == nil || appLink.deviceUid == deviceUid)
            })
        )
        return links.map { $0.toAppEntityWithIcon() }
    }

    public func entities(deviceUid: String?) throws -> [AppLinkAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<AppLink>(
                predicate: #Predicate {
                    deviceUid == nil || $0.deviceUid == deviceUid
                },
                sortBy: [SortDescriptor(\AppLink.lastSelected, order: .reverse)]
            )
        )
        return links.map { $0.toAppEntityWithIcon() }
    }

    public func deleteEntities(deviceUid: String?) throws {
        let links = try modelContext.fetch(
            FetchDescriptor<AppLink>(
                predicate: #Predicate {
                    deviceUid == nil || $0.deviceUid == deviceUid
                }
            )
        )
        for link in links {
            modelContext.delete(link)
        }
    }
}
