import Foundation

struct HomeIdea: Codable, Equatable {
    var title: String
    var why: String
    var place: String
    var priority: String
    var done: Bool

    enum CodingKeys: String, CodingKey {
        case title, why, priority, done
        case place = "where"
    }
}

// What homescan.js cleanIdeas returns. HomeScanRules makes it
struct HomeScanResult: Codable, Equatable {
    var status: String // "ok" | "notRoom" | "empty" | "unreadable"
    var room: String
    var ideas: [HomeIdea]
    var dropped: Int
}

// The photo is never saved, only the room and its ideas
struct HomeScan: Codable, Equatable {
    var ts: Int // ms since 1970, like check-ins
    var room: String
    var ideas: [HomeIdea]
}

extension Store {
    static let homeScansKey = "neurotrace:homescans"

    // Oldest first
    static func getHomeScans() -> [HomeScan] {
        (try? JSONDecoder().decode([HomeScan].self, from: Data((defaults.string(forKey: homeScansKey) ?? "[]").utf8))) ?? []
    }

    static func setHomeScans(_ scans: [HomeScan]) {
        guard let data = try? JSONEncoder().encode(scans) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: homeScansKey)
    }

    static func clearHomeScans() {
        defaults.removeObject(forKey: homeScansKey)
    }
}
