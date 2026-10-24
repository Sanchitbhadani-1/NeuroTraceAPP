import Foundation

struct TapSample: Codable, Equatable {
    var t: Double
    var gap: Double?
}

// Same fields as tapping.js analyzeTaps returns. Tapping.analyzeTaps makes it
struct TapResult: Codable, Equatable {
    var counted: Bool
    var taps: Int
    var duration: Double?
    var rate: Double?
    var rhythmCv: Double?
    var meanOpening: Double?
    var openingChange: Double?
    var rateChange: Double?
    var pauses: Int
    var tapTimes: [Double]
    var openings: [Double]
}

// ponytail: raw camera samples aren't kept, add them if a tap reference ever needs the curves
struct TapTest: Codable, Equatable {
    var ts: Int // ms since 1970, like check-ins
    var hand: String
    var result: TapResult
}

extension Store {
    static let tapsKey = "neurotrace:taps"

    // Oldest first
    static func getTapTests() -> [TapTest] {
        (try? JSONDecoder().decode([TapTest].self, from: Data((defaults.string(forKey: tapsKey) ?? "[]").utf8))) ?? []
    }

    static func saveTapTest(_ test: TapTest) {
        guard let data = try? JSONEncoder().encode(getTapTests() + [test]) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: tapsKey)
    }

    static func clearTapTests() {
        defaults.removeObject(forKey: tapsKey)
    }
}
