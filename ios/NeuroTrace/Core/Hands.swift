// HANDS.SWIFT COMPARES THE LEFT HAND WITH THE RIGHT HAND
// IT CALLS app/core/hands.js THROUGH JSCORE

import Foundation

// The parts of a check in that latestPair reads
protocol HandedCheckin {
    var ts: Int { get }
    var hand: String { get }
    var inputType: String? { get }
}

// Saved check ins can be passed to latestPair
extension AssessmentRecord: HandedCheckin {}

// Finds a left and right pair and compares the two hands
enum Hands {

    // One measure for both hands, where diff is left minus right
    struct Row: Equatable, Decodable {
        var key: String
        var left: Double
        var right: Double
        var diff: Double
    }

    // The parts of a check in sent to hands.js, where i is the record's place in the list
    private struct Handed: Codable {
        var i: Int
        var ts: Int
        var hand: String
        var inputType: String?
    }

    // What latestPair sends to hands.js
    private struct PairInput: Encodable {
        var records: [Handed]
        var maxDaysApart: Double
    }

    // The left and right check ins hands.js sends back
    private struct Pair: Decodable {
        var left: Handed
        var right: Handed
    }

    // Find a left and right pair with the same input type, at most maxDaysApart days apart
    static func latestPair<R: HandedCheckin>(_ records: [R], maxDaysApart: Double = 7) -> (left: R, right: R)? {

        // Number each record and keep only the parts hands.js reads
        let handed = records.enumerated().map { (i, r) in Handed(i: i, ts: r.ts, hand: r.hand, inputType: r.inputType) }

        // Ask hands.js for the pair, then look up the matching records by their numbers
        let pair: Pair? = JSCore.must("hands.latestPair", PairInput(records: handed, maxDaysApart: maxDaysApart))
        return pair.map { p in (left: records[p.left.i], right: records[p.right.i]) }
    }

    // The percentile for each measure of one hand
    private struct Percentiles: Encodable {
        var measurePct: [String: Double]
    }

    // What compareHands sends to hands.js
    private struct CompareInput: Encodable {
        var left: Percentiles
        var right: Percentiles
        var order: [String]
    }

    // Compare the percentiles for each measure, largest difference first, where diff is left minus right
    static func compareHands(left: [String: Double], right: [String: Double], order: [String] = NTFeatures.spiralFeatureOrder) -> [Row] {
        JSCore.must("hands.compareHands", CompareInput(left: Percentiles(measurePct: left), right: Percentiles(measurePct: right), order: order))
    }
}
