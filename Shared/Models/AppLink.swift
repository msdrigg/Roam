import Foundation
import SwiftData
import os

@Model
public final class AppLink: Identifiable, Decodable {
    public let id: String
    public let type: String
    public let name: String
    public var lastSelected: Date? = nil
    @Attribute(.externalStorage) public var icon: Data?
    
    init(id: String, type: String, name: String, icon: Data? = nil, devices: [Device] = []) {
        self.id = id
        self.type = type
        self.name = name
        self.icon = icon
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        
        let singleValueContainer = try decoder.singleValueContainer()
        name = try singleValueContainer.decode(String.self)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, name
    }
}

public func getTestingAppLinks() -> [AppLink] {
    return [
        AppLink(id: "1", type: "appl", name: "Netflix", icon: nil),
        AppLink(id: "5", type: "appl", name: "Hulu", icon: nil),
        AppLink(id: "3", type: "appl", name: "Spotify with test long name", icon: nil),
        AppLink(id: "2", type: "appl", name: "Showtime (no icon)"),
        AppLink(id: "4", type: "appl", name: "Disney another sweet long name", icon: nil),
        AppLink(id: "6", type: "appl", name: "Disney another sweet long name", icon: nil),
        AppLink(id: "7", type: "appl", name: "Disney another sweet long name", icon: nil),
        AppLink(id: "7", type: "appl2", name: "Disney another", icon: nil),
    ]
}

func loadPreviewAsset(_ assetName: String) -> Data? {
    let data: Data
    
    guard let file = Bundle.main.url(forResource: assetName, withExtension: nil)
    else {
        os_log(.error, "Couldn't find \(assetName) in preview xcassets.")
        return nil
    }
    
    
    do {
        data = try Data(contentsOf: file)
    } catch {
        os_log(.error, "Couldn't load \(assetName) from preview xcassets:\n\(error)")
        return nil
    }
    return data
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
    
    public func entities(for identifiers: [AppLinkAppEntity.ID]) throws -> [AppLinkAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<AppLink>(predicate: #Predicate { appLink in
                identifiers.contains(appLink.id)
            })
        )
        return links.map {$0.toAppEntity()}
    }
    
    public func entities(matching string: String) throws -> [AppLinkAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<AppLink>(predicate: #Predicate<AppLink> { appLink in
                appLink.name.contains(string)
            })
        )
        return links.map {$0.toAppEntity()}
    }
    
    public func suggestedEntities() throws -> [AppLinkAppEntity] {
        let links = try modelContext.fetch(
            FetchDescriptor<AppLink>()
        )
        return links.map {$0.toAppEntity()}
    }
}
