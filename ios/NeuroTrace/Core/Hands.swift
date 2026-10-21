import Foundation

// Left hand against right hand. Mihir's app/hands.js does the work, called through JSCore

// What latestPair needs from a check-in
protocol HandedCheckin {
    var ts: Int { get }
    var hand: String { get }
    var inputType: String? { get }
}

extension AssessmentRecord: HandedCheckin {}

enum Hands {
    // One measure for both hands. diff is left minus right
    struct Row: Equatable, Decodable {
        var key: String
        var left: Double
        var right: Double
        var diff: Double
    }

    // What hands.js reads from a check-in. i says which record it was, so the pair comes back as the same records
    private struct Handed: Codable {
        var i: Int
        var ts: Int
        var hand: String
        var inputType: String?
    }

    private struct PairInput: Encodable {
        var records: [Handed]
        var maxDaysApart: Double
    }

    private struct Pair: Decodable {
        var left: Handed
        var right: Handed
    }

    // find a left and right pair with the same input type, at most maxDaysApart days apart
    static func latestPair<R: HandedCheckin>(_ records: [R], maxDaysApart: Double = 7) -> (left: R, right: R)? {
        let handed = records.enumerated().map { (i, r) in Handed(i: i, ts: r.ts, hand: r.hand, inputType: r.inputType) }
        let pair: Pair? = JSCore.must("hands.latestPair", PairInput(records: handed, maxDaysApart: maxDaysApart))
        return pair.map { p in (left: records[p.left.i], right: records[p.right.i]) }
    }

    private struct Percentiles: Encodable {
        var measurePct: [String: Double]
    }

    private struct CompareInput: Encodable {
        var left: Percentiles
        var right: Percentiles
        var order: [String]
    }

    // compare percentiles for each measure, largest difference first. diff is left minus right
    static func compareHands(left: [String: Double], right: [String: Double], order: [String] = NTFeatures.spiralFeatureOrder) -> [Row] {
        JSCore.must("hands.compareHands", CompareInput(left: Percentiles(measurePct: left), right: Percentiles(measurePct: right), order: order))
    }
}
