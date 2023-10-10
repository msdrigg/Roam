import Foundation
import SwiftData

final class AppLink: Codable, Identifiable {
    let name: String
    var link: String
    var id: String
    
    
    public init(name: String, id: String, link: String) {
        self.name = name
        self.id = id
        self.link = link
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(id, forKey: .id)
        try container.encode(link, forKey: .link)
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.id = try container.decode(String.self, forKey: .id)
        self.link = try container.decode(String.self, forKey: .link)
    }
    
    private enum CodingKeys: String, CodingKey {
        case name
        case id
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
