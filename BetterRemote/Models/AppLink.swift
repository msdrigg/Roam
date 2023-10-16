//
//  AppLink.swift
//  BetterRemote
//
//  Created by Scott Driggers on 10/13/23.
//

import Foundation
import SwiftData

@Model
final class AppLink: Identifiable, Decodable, Encodable {
    let id: String
    let type: String
    let name: String
    @Attribute(.externalStorage) var icon: Data?
    
    init(id: String, type: String, name: String, icon: Data? = nil) {
        self.id = id
        self.type = type
        self.name = name
        self.icon = icon
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        
        let singleValueContainer = try decoder.singleValueContainer()
        name = try singleValueContainer.decode(String.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(name)
    }
    
    enum CodingKeys: String, CodingKey {
        case id, type, name
    }
}

func getTestingAppLinks() -> [AppLink] {
    let netflixIcon = loadPreviewAsset("netflix.png")
    let huluIcon = loadPreviewAsset("hulu.png")
    let spotifyIcon = loadPreviewAsset("spotify.png")
    let disneyIcon = loadPreviewAsset("disney.png")
    return [
        AppLink(id: "1", type: "appl", name: "Netflix", icon: netflixIcon),
        AppLink(id: "5", type: "appl", name: "Hulu", icon: huluIcon),
        AppLink(id: "3", type: "appl", name: "Spotify with test long name", icon: spotifyIcon),
        AppLink(id: "2", type: "appl", name: "Showtime (no icon)"),
        AppLink(id: "4", type: "appl", name: "Disney another sweet long name", icon: disneyIcon),
        AppLink(id: "6", type: "appl", name: "Disney another sweet long name", icon: disneyIcon),
        AppLink(id: "7", type: "appl", name: "Disney another sweet long name", icon: disneyIcon),
    ]
}

func loadPreviewAsset(_ assetName: String) -> Data? {
    let data: Data
    
    guard let file = Bundle.main.url(forResource: assetName, withExtension: nil)
    else {
        print("Couldn't find \(assetName) in preview xcassets.")
        return nil
    }
    
    
    do {
        data = try Data(contentsOf: file)
    } catch {
        print("Couldn't load \(assetName) from preview xcassets:\n\(error)")
        return nil
    }
    return data
}
