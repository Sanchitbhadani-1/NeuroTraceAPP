// TAPTESTS.SWIFT HOLDS THE FINGER TAPPING TEST TYPES
// IT ALSO SAVES, LOADS AND CLEARS SAVED TAP TESTS ON THE DEVICE

import Foundation

// One camera frame, with its time in seconds and the gap between the fingertips, or nil
struct TapSample: Codable, Equatable {
    var t: Double
    var gap: Double?
}

// The same fields that analyzeTaps in tapping.js gives back
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

// One saved tap test, with the hand and the result but not the camera samples
struct TapTest: Codable, Equatable {

    // When the test was taken, in milliseconds since 1970
    var ts: Int
    var hand: String
    var result: TapResult
}

// Saving and loading tap tests
extension Store {

    // The key the tests are saved under
    static let tapsKey = "neurotrace:taps"

    // Load every saved test, oldest first, or an empty list if there are none
    static func getTapTests() -> [TapTest] {
        (try? JSONDecoder().decode([TapTest].self, from: Data((defaults.string(forKey: tapsKey) ?? "[]").utf8))) ?? []
    }

    // Add one test to the end of the saved list
    static func saveTapTest(_ test: TapTest) {
        guard let data = try? JSONEncoder().encode(getTapTests() + [test]) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: tapsKey)
    }

    // Delete every saved test
    static func clearTapTests() {
        defaults.removeObject(forKey: tapsKey)
    }
}
