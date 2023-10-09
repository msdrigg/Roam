//
//  AppLink.swift
//  MacRokuRemote
//
//  Created by Scott Driggers on 10/7/23.
//

import Foundation
import SwiftData

final class AppLink: Codable, Identifiable {
    let name: String
    let website: String
    var link: String?
    var index: UInt8?
    var id: String { website }
    
    
    public init(name: String, website: String, link: String? = nil, index: UInt8? = nil) {
        self.name = name
        self.website = website
        self.link = link
        self.index = index
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(website, forKey: .website)
        try container.encode(link, forKey: .link)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.website = try container.decode(String.self, forKey: .website)
        self.link = try container.decodeIfPresent(String.self, forKey: .link)
    }
    
    private enum CodingKeys: String, CodingKey {
        case name
        case website
        case link
    }
}

func loadDefaultAppLinks() -> [AppLink] {
    loadFromFile("appLinks.json")
}

func loadFromFile<T: Decodable>(_ filename: String) -> T {
    let data: Data
    
    
    guard let file = Bundle.main.url(forResource: filename, withExtension: nil)
    else {
        fatalError("Couldn't find \(filename) in main bundle.")
    }
    
    
    do {
        data = try Data(contentsOf: file)
    } catch {
        fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
    }
    
    
    do {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    } catch {
        fatalError("Couldn't parse \(filename) as \(T.self):\n\(error)")
    }
}
