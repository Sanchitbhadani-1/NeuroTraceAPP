// HOMESCANS.SWIFT HOLDS THE HOME SAFETY SCAN TYPES
// IT ALSO SAVES, LOADS AND CLEARS SAVED SCANS ON THE DEVICE

import Foundation

// One idea for a room
struct HomeIdea: Codable, Equatable {
    var title: String
    var why: String
    var place: String
    var priority: String
    var done: Bool

    // Save place as "where"
    enum CodingKeys: String, CodingKey {
        case title, why, priority, done
        case place = "where"
    }
}

// What cleanIdeas in homescan.js gives back
struct HomeScanResult: Codable, Equatable {

    // "ok", "notRoom", "empty" or "unreadable"
    var status: String
    var room: String
    var ideas: [HomeIdea]
    var dropped: Int
}

// One saved scan, with the room and its ideas
struct HomeScan: Codable, Equatable {

    // When the scan was made, in milliseconds since 1970
    var ts: Int
    var room: String
    var ideas: [HomeIdea]
}

// Saving and loading home scans
extension Store {

    // The key the scans are saved under
    static let homeScansKey = "neurotrace:homescans"

    // Load every saved scan, oldest first, or an empty list if there are none
    static func getHomeScans() -> [HomeScan] {
        (try? JSONDecoder().decode([HomeScan].self, from: Data((defaults.string(forKey: homeScansKey) ?? "[]").utf8))) ?? []
    }

    // Save the list of scans as JSON text
    static func setHomeScans(_ scans: [HomeScan]) {
        guard let data = try? JSONEncoder().encode(scans) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: homeScansKey)
    }

    // Delete every saved scan
    static func clearHomeScans() {
        defaults.removeObject(forKey: homeScansKey)
    }
}
