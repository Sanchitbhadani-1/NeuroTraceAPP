import Foundation

// The medication diary. Mihir's app/meds.js does the timing math, called through JSCore. The helpers at the
// bottom only exist in the iPad app, to turn saved check-ins into what meds.js reads

enum Meds {
    // How many check-ins before the chart is shown
    static let minCheckins: Int = JSCore.must("meds.MIN_CHECKINS")

    // What the functions below read from each check-in
    struct Checkin: Equatable, Encodable {
        var ts: Int
        var hand: String?
        var inputType: String?
        var measurePct: [String: Double]
    }

    // One time window after a dose, with how many check-ins landed in it and their median
    struct Bin: Equatable, Codable {
        var from: Double
        var to: Double
        var n: Int
        var median: Double?
    }

    struct Timing: Equatable, Decodable {
        var ready: Bool
        var counted: Int
        var bins: [Bin]
        var best: Bin?
    }

    private struct SinceInput: Encodable {
        var ts: Int
        var doses: [Dose]
        var maxHours: Double
    }

    // how many hours since the last dose, or nil
    static func hoursSinceDose(ts: Int, doses: [Dose], maxHours: Double = 12) -> Double? {
        JSCore.must("meds.hoursSinceDose", SinceInput(ts: ts, doses: doses, maxHours: maxHours))
    }

    private struct GroupInput: Encodable {
        var checkins: [Checkin]
        var doses: [Dose]
        var measure: String
        var edges: [Double]
    }

    // group check-in values by hours since last dose. return counts and medians
    static func groupByHoursSinceDose(checkins: [Checkin], doses: [Dose], measure: String, edges: [Double] = [0, 1, 2, 3, 4, 6, 12]) -> [Bin] {
        JSCore.must("meds.groupByHoursSinceDose", GroupInput(checkins: checkins, doses: doses, measure: measure, edges: edges))
    }

    private struct HighestInput: Encodable {
        var bins: [Bin]
        var minN: Int
    }

    // find the highest median of bins with enough check-ins
    static func highestBin(bins: [Bin], minN: Int = 2) -> Bin? {
        JSCore.must("meds.highestBin", HighestInput(bins: bins, minN: minN))
    }

    private struct TimingInput: Encodable {
        var checkins: [Checkin]
        var doses: [Dose]
        var measure: String
        var hand: String?
        var inputType: String?
    }

    // build the dose timing summary. check if enough data is available
    static func doseTiming(checkins: [Checkin], doses: [Dose], measure: String, hand: String? = nil, inputType: String? = nil) -> Timing {
        JSCore.must("meds.doseTiming", TimingInput(checkins: checkins, doses: doses, measure: measure, hand: hand, inputType: inputType))
    }

    // For each measure, whether a higher percentile means better drawing. Main wobble frequency
    // isn't better or worse either way, so it's left out
    static let higherIsBetter: [String: Bool] = [
        "spiral_duration": false,
        "spiral_max_deviation": false, "spiral_mean_deviation": false, "spiral_std_deviation": false,
        "spiral_major_reversals": false,
        "spiral_mean_speed": true, "spiral_std_speed": false,
        "spiral_ldlj": true, "spiral_sparc": true,
        "spiral_tremor_4_6": false, "spiral_tremor_6_12": false,
    ]

    // The measures the timing chart lets you pick from
    static let timingMeasures = ["spiral_mean_speed", "spiral_ldlj", "spiral_mean_deviation", "spiral_tremor_4_6"]

    // Turn percentiles around where lower is better, so a higher number always means better drawing.
    // That way highestBin always finds the best time after a dose
    static func betterPct(_ measurePct: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (key, pct) in measurePct {
            guard let higher = higherIsBetter[key] else { continue }
            out[key] = higher ? pct : 1 - pct
        }
        return out
    }

    // What doseTiming reads from saved check-ins. measurePct picks the percentiles to use for each one
    static func checkins(_ records: [AssessmentRecord], _ measurePct: (AssessmentRecord) -> [String: Double]? = { r in r.result?.measurePct }) -> [Checkin] {
        records.compactMap { r in
            guard let pct = measurePct(r) else { return nil }
            return Checkin(ts: r.ts, hand: r.hand, inputType: r.inputType, measurePct: betterPct(pct))
        }
    }

    // The hand and pen or finger used for the most check-ins. records come newest first, so a tie goes
    // to the one used most recently. The timing chart sticks to this, so one check-in with the other
    // hand doesn't switch the chart over to that hand
    static func mainSetup(_ records: [AssessmentRecord]) -> (hand: String, inputType: String?)? {
        let key = { (r: AssessmentRecord) in r.hand + "|" + (r.inputType ?? "") }
        var counts: [String: Int] = [:]
        for r in records { counts[key(r), default: 0] += 1 }
        var best: AssessmentRecord? = nil
        for r in records where best == nil || counts[key(r)]! > counts[key(best!)]! { best = r }
        return best.map { b in (hand: b.hand, inputType: b.inputType) }
    }
}
