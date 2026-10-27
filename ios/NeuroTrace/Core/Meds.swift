// MEDS.SWIFT RUNS THE MEDICATION DIARY'S TIMING MATH
// IT CALLS app/core/meds.js THROUGH JSCORE
// IT ALSO TURNS SAVED CHECK INS INTO WHAT MEDS.JS READS

import Foundation

// The medication diary's timing functions
enum Meds {

    // How many check ins are needed before the chart is shown
    static let minCheckins: Int = JSCore.must("meds.MIN_CHECKINS")

    // The parts of a check in that the functions below read
    struct Checkin: Equatable, Encodable {
        var ts: Int
        var hand: String?
        var inputType: String?
        var measurePct: [String: Double]
    }

    // One time window after a dose, with how many check ins landed in it and their median
    struct Bin: Equatable, Codable {
        var from: Double
        var to: Double
        var n: Int
        var median: Double?
    }

    // The dose timing summary, with whether it is ready, how many check ins counted, the windows and the best window
    struct Timing: Equatable, Decodable {
        var ready: Bool
        var counted: Int
        var bins: [Bin]
        var best: Bin?
    }

    // What hoursSinceDose sends to meds.js
    private struct SinceInput: Encodable {
        var ts: Int
        var doses: [Dose]
        var maxHours: Double
    }

    // Give back how many hours since the last dose, or nil
    static func hoursSinceDose(ts: Int, doses: [Dose], maxHours: Double = 12) -> Double? {
        JSCore.must("meds.hoursSinceDose", SinceInput(ts: ts, doses: doses, maxHours: maxHours))
    }

    // What groupByHoursSinceDose sends to meds.js
    private struct GroupInput: Encodable {
        var checkins: [Checkin]
        var doses: [Dose]
        var measure: String
        var edges: [Double]
    }

    // Group check in values by hours since the last dose, and give back the counts and medians
    static func groupByHoursSinceDose(checkins: [Checkin], doses: [Dose], measure: String, edges: [Double] = [0, 1, 2, 3, 4, 6, 12]) -> [Bin] {
        JSCore.must("meds.groupByHoursSinceDose", GroupInput(checkins: checkins, doses: doses, measure: measure, edges: edges))
    }

    // What highestBin sends to meds.js
    private struct HighestInput: Encodable {
        var bins: [Bin]
        var minN: Int
    }

    // Find the window with the highest median among windows with at least minN check ins
    static func highestBin(bins: [Bin], minN: Int = 2) -> Bin? {
        JSCore.must("meds.highestBin", HighestInput(bins: bins, minN: minN))
    }

    // What doseTiming sends to meds.js
    private struct TimingInput: Encodable {
        var checkins: [Checkin]
        var doses: [Dose]
        var measure: String
        var hand: String?
        var inputType: String?
    }

    // Build the dose timing summary and check if there are enough check ins
    static func doseTiming(checkins: [Checkin], doses: [Dose], measure: String, hand: String? = nil, inputType: String? = nil) -> Timing {
        JSCore.must("meds.doseTiming", TimingInput(checkins: checkins, doses: doses, measure: measure, hand: hand, inputType: inputType))
    }

    // For each measure, true when a higher percentile means better drawing
    // Main wobble frequency is left out
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

    // Flip the percentiles where lower is better, so a higher number always means better drawing
    // Measures not in higherIsBetter are left out
    static func betterPct(_ measurePct: [String: Double]) -> [String: Double] {
        var out: [String: Double] = [:]
        for (key, pct) in measurePct {
            guard let higher = higherIsBetter[key] else { continue }
            out[key] = higher ? pct : 1 - pct
        }
        return out
    }

    // Turn saved check ins into what doseTiming reads, using measurePct to pick each one's percentiles
    // Check ins with no percentiles are skipped
    static func checkins(_ records: [AssessmentRecord], _ measurePct: (AssessmentRecord) -> [String: Double]? = { r in r.result?.measurePct }) -> [Checkin] {
        records.compactMap { r in
            guard let pct = measurePct(r) else { return nil }
            return Checkin(ts: r.ts, hand: r.hand, inputType: r.inputType, measurePct: betterPct(pct))
        }
    }

    // Give back the hand and the pen or finger used for the most check ins
    // A tie goes to the first one in the list
    static func mainSetup(_ records: [AssessmentRecord]) -> (hand: String, inputType: String?)? {

        // Count the check ins for each hand and input type
        let key = { (r: AssessmentRecord) in r.hand + "|" + (r.inputType ?? "") }
        var counts: [String: Int] = [:]
        for r in records { counts[key(r), default: 0] += 1 }

        // Keep the first record whose count is higher than every one before it
        var best: AssessmentRecord? = nil
        for r in records where best == nil || counts[key(r)]! > counts[key(best!)]! { best = r }
        return best.map { b in (hand: b.hand, inputType: b.inputType) }
    }
}
