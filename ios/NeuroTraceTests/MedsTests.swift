// MEDSTESTS.SWIFT CHECKS DOSE TIMING, TIME GROUP MIDDLE VALUES, TIES, AND THE SMALLEST NUMBER OF CHECK INS
// IT USES THE SAME CASES AS APP/TOOLS/MEDS-CHECK.MJS, AND ALSO CHECKS HOW DOSES AND MEDICINE ARE SAVED

import Foundation
import XCTest
// Use the NeuroTraceCore module when it exists, or the app if it doesn't
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

// One hour in milliseconds, the measure used in most tests, and one dose at time 0
private let H = 3_600_000.0
private let speed = "spiral_mean_speed"
private let doses = [Dose(ts: 0)]

// Turns hours after the first dose into milliseconds
private func at(_ hours: Double) -> Int { Int((hours * H).rounded()) }

// Makes a check in at a given hour with a speed value, using the right hand and a pencil unless given
private func checkin(_ hours: Double, _ value: Double, _ hand: String = "right", _ inputType: String = "pencil") -> Meds.Checkin {
    Meds.Checkin(ts: at(hours), hand: hand, inputType: inputType, measurePct: [speed: value])
}

// The tests for medication timing
final class MedsTests: XCTestCase {

    // Check the hours since a dose, the time groups, the best group, and the chart's check in counts
    func testMeds() async throws {

        // Check that the hours count from the newest dose before the check in, up to 12 hours, and nil with no dose before it
        XCTAssertEqual(Meds.hoursSinceDose(ts: at(10), doses: [Dose(ts: at(8))]), 2)
        XCTAssertEqual(Meds.hoursSinceDose(ts: at(10), doses: [Dose(ts: at(7)), Dose(ts: at(11)), Dose(ts: at(9))]), 1)
        XCTAssertNil(Meds.hoursSinceDose(ts: at(10), doses: [Dose(ts: at(11))]))
        XCTAssertNil(Meds.hoursSinceDose(ts: at(10), doses: []))
        XCTAssertNil(Meds.hoursSinceDose(ts: at(25), doses: [Dose(ts: at(12))]))
        XCTAssertEqual(Meds.hoursSinceDose(ts: at(24), doses: [Dose(ts: at(12))]), 12)
        XCTAssertEqual(Meds.hoursSinceDose(ts: at(10), doses: [Dose(ts: at(10))]), 0)

        // Group check ins by hours since the dose, with some past 12 hours, one with no value, and one that is not a number
        let bins = Meds.groupByHoursSinceDose(
            checkins: [checkin(0.5, 0.2), checkin(1.5, 0.4), checkin(1.7, 0.6), checkin(12, 0.9), checkin(13, 0.5),
                Meds.Checkin(ts: at(3), measurePct: [:]), Meds.Checkin(ts: at(3), measurePct: [speed: .nan])],
            doses: doses,
            measure: speed
        )

        // Check the six groups, how many check ins land in each, and the middle values
        XCTAssertEqual(bins.count, 6)
        XCTAssertEqual(bins.map { b in [b.from, b.to] }, [[0, 1], [1, 2], [2, 3], [3, 4], [4, 6], [6, 12]])
        XCTAssertEqual(bins.map { b in b.n }, [1, 2, 0, 0, 0, 1])
        XCTAssertEqual(bins[1].median, 0.5)
        XCTAssertNil(bins[2].median)

        // Check the middle value of an odd number of check ins
        let odd = Meds.groupByHoursSinceDose(checkins: [checkin(1.5, 0.9), checkin(1.5, 0.1), checkin(1.5, 0.25)], doses: doses, measure: speed)
        XCTAssertEqual(odd[1].median, 0.25)

        // Check that the best group skips groups with only one check in, and gives nil when no group has two
        XCTAssertEqual(Meds.highestBin(bins: bins)?.from, 1)
        let lucky = Meds.groupByHoursSinceDose(checkins: [checkin(0.5, 0.9), checkin(1.5, 0.1), checkin(1.6, 0.2)], doses: doses, measure: speed)
        XCTAssertEqual(Meds.highestBin(bins: lucky)?.from, 1)
        XCTAssertNil(Meds.highestBin(bins: Meds.groupByHoursSinceDose(checkins: [checkin(0.5, 0.9)], doses: doses, measure: speed)))

        // Check that a tie goes to the earlier group
        let tie = Meds.groupByHoursSinceDose(checkins: [checkin(0.2, 0.5), checkin(0.4, 0.5), checkin(1.2, 0.5), checkin(1.4, 0.5)], doses: doses, measure: speed)
        XCTAssertEqual(Meds.highestBin(bins: tie)?.from, 0)

        // Check that the chart needs 6 check ins, and is ready with its best group at one hour once it has them
        let five = [checkin(1.1, 0.5), checkin(1.2, 0.5), checkin(2.1, 0.4), checkin(2.2, 0.4), checkin(5, 0.3)]
        XCTAssertEqual(Meds.minCheckins, 6)
        XCTAssertFalse(Meds.doseTiming(checkins: five, doses: doses, measure: speed, hand: "right").ready)
        let timing = Meds.doseTiming(checkins: five + [checkin(5.5, 0.3)], doses: doses, measure: speed, hand: "right")
        XCTAssertTrue(timing.ready)
        XCTAssertEqual(timing.counted, 6)
        XCTAssertEqual(timing.best?.from, 1)

        // Check that only the given hand and pen or finger are counted, and every check in counts when no hand is given
        XCTAssertEqual(Meds.doseTiming(checkins: five + [checkin(5.5, 0.3, "left")], doses: doses, measure: speed, hand: "right").counted, 5)
        XCTAssertEqual(Meds.doseTiming(checkins: five + [checkin(5.5, 0.3, "right", "finger")], doses: doses, measure: speed, inputType: "pencil").counted, 5)
        XCTAssertEqual(Meds.doseTiming(checkins: five + [checkin(5.5, 0.3, "left")], doses: doses, measure: speed).counted, 6)

        // Check that percentiles where lower is better are flipped, and the main wobble frequency is left out
        let better = Meds.betterPct(["spiral_mean_speed": 0.7, "spiral_duration": 0.7, "spiral_tremor_dominant_hz": 0.5])
        XCTAssertEqual(better["spiral_mean_speed"], 0.7)
        XCTAssertEqual(better["spiral_duration"]!, 0.3, accuracy: 1e-12)
        XCTAssertNil(better["spiral_tremor_dominant_hz"])

        // Check that every timing measure and every spiral measure except the main wobble frequency has a better direction
        for key in Meds.timingMeasures { XCTAssertNotNil(Meds.higherIsBetter[key], "\(key) has no direction") }
        for key in NTFeatures.spiralFeatureOrder where key != "spiral_tremor_dominant_hz" {
            XCTAssertNotNil(Meds.higherIsBetter[key], "\(key) has no direction")
        }

        // Makes a saved left hand check in, with or without a result
        let record = { (ts: Int, result: Bool) in
            AssessmentRecord(id: nil, ts: ts, task: "spiral", hand: "left", ageChoice: nil, bracketChoice: nil, inputType: "pencil", deviceLabel: "",
                trials: nil, features: nil,
                result: result ? Score.Result(features: [:], bracketKey: "all", referenceN: 1, deviceMatched: true, trialsPerSession: 3, tier: 0,
                    measurePct: ["spiral_mean_speed": 0.25, "spiral_mean_deviation": 0.25], topSignals: [], score: 0.5, scorePct: 0.5) : nil)
        }

        // Check that saved check ins without a result are skipped, and lower is better percentiles are flipped
        let made = Meds.checkins([record(at(1), true), record(at(2), false)])
        XCTAssertEqual(made.count, 1)
        XCTAssertEqual(made[0], Meds.Checkin(ts: at(1), hand: "left", inputType: "pencil", measurePct: ["spiral_mean_speed": 0.25, "spiral_mean_deviation": 0.75]))

        // Makes a saved check in with a given hand and pen or finger
        let drawn = { (ts: Int, hand: String, input: String) in
            AssessmentRecord(id: nil, ts: ts, task: "spiral", hand: hand, ageChoice: nil, bracketChoice: nil, inputType: input, deviceLabel: "",
                trials: nil, features: nil, result: nil)
        }

        // Check that the chart uses the hand and pen or finger used most, even when the newest check in is different
        let most = Meds.mainSetup([drawn(at(5), "left", "pencil"), drawn(at(4), "right", "pencil"), drawn(at(3), "right", "pencil")])
        XCTAssertEqual(most?.hand, "right")
        XCTAssertEqual(most?.inputType, "pencil")

        // Check that a tie goes to the newest check in, and no check ins gives nil
        let tied = Meds.mainSetup([drawn(at(5), "left", "touch"), drawn(at(4), "right", "pencil")])
        XCTAssertEqual(tied?.hand, "left")
        XCTAssertEqual(tied?.inputType, "touch")
        XCTAssertNil(Meds.mainSetup([]))

        print("MEDS OK")
    }

    // Check that doses and the medicine save, list, and delete
    func testDoseStore() async throws {

        // Point the store at an empty test folder, and put the real one back at the end
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("neurotrace-doses-\(UUID().uuidString)")
        let saved = Store.folder
        Store.folder = folder
        defer {
            try? FileManager.default.removeItem(at: folder)
            Store.folder = saved
        }

        // Save three doses, the last one for a time between the other two
        let first = try await Store.saveDose(Dose(ts: 5_000))
        let second = try await Store.saveDose(Dose(ts: 9_000))
        _ = try await Store.saveDose(Dose(ts: 7_000))

        // Check that doses list newest first by time
        var listed = try await Store.listDoses()
        XCTAssertEqual(listed.map { d in d.ts }, [9_000, 7_000, 5_000])

        // Check that deleting a dose removes only that one
        try await Store.deleteDose(second)
        listed = try await Store.listDoses()
        XCTAssertEqual(listed.map { d in d.ts }, [7_000, 5_000])
        XCTAssertEqual(listed.last?.id, first)

        // Use empty test settings, and put the real ones back at the end
        let suite = "neurotrace-medication-check-\(UUID().uuidString)"
        let savedDefaults = Store.defaults
        Store.defaults = UserDefaults(suiteName: suite)!
        defer {
            Store.defaults.removePersistentDomain(forName: suite)
            Store.defaults = savedDefaults
        }

        // Check that the medicine starts empty and saves its name
        XCTAssertEqual(Store.getMedication(), Store.Medication())
        Store.setMedication(Store.Medication(name: "Levodopa", schedule: "1 tablet at 8 AM"))
        XCTAssertEqual(Store.getMedication().name, "Levodopa")

        print("DOSE STORE OK")
    }
}
