// check dose timing, bin medians, ties, and the minimum check-in count. The same cases as Mihir's
// app/tools/meds-check.mjs, so the Swift and JavaScript versions agree

import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

private let H = 3_600_000.0
private let speed = "spiral_mean_speed"
private let doses = [Dose(ts: 0)]

// hours after the first dose, in milliseconds
private func at(_ hours: Double) -> Int { Int((hours * H).rounded()) }

private func checkin(_ hours: Double, _ value: Double, _ hand: String = "right", _ inputType: String = "pencil") -> Meds.Checkin {
    Meds.Checkin(ts: at(hours), hand: hand, inputType: inputType, measurePct: [speed: value])
}

final class MedsTests: XCTestCase {
    func testMeds() async throws {
        XCTAssertEqual(Meds.hoursSinceDose(ts: at(10), doses: [Dose(ts: at(8))]), 2)
        XCTAssertEqual(Meds.hoursSinceDose(ts: at(10), doses: [Dose(ts: at(7)), Dose(ts: at(11)), Dose(ts: at(9))]), 1)
        XCTAssertNil(Meds.hoursSinceDose(ts: at(10), doses: [Dose(ts: at(11))]))
        XCTAssertNil(Meds.hoursSinceDose(ts: at(10), doses: []))
        XCTAssertNil(Meds.hoursSinceDose(ts: at(25), doses: [Dose(ts: at(12))]))
        XCTAssertEqual(Meds.hoursSinceDose(ts: at(24), doses: [Dose(ts: at(12))]), 12)
        XCTAssertEqual(Meds.hoursSinceDose(ts: at(10), doses: [Dose(ts: at(10))]), 0)

        let bins = Meds.groupByHoursSinceDose(
            checkins: [checkin(0.5, 0.2), checkin(1.5, 0.4), checkin(1.7, 0.6), checkin(12, 0.9), checkin(13, 0.5),
                Meds.Checkin(ts: at(3), measurePct: [:]), Meds.Checkin(ts: at(3), measurePct: [speed: .nan])],
            doses: doses,
            measure: speed
        )
        XCTAssertEqual(bins.count, 6)
        XCTAssertEqual(bins.map { b in [b.from, b.to] }, [[0, 1], [1, 2], [2, 3], [3, 4], [4, 6], [6, 12]])
        XCTAssertEqual(bins.map { b in b.n }, [1, 2, 0, 0, 0, 1])
        XCTAssertEqual(bins[1].median, 0.5)
        XCTAssertNil(bins[2].median)

        let odd = Meds.groupByHoursSinceDose(checkins: [checkin(1.5, 0.9), checkin(1.5, 0.1), checkin(1.5, 0.25)], doses: doses, measure: speed)
        XCTAssertEqual(odd[1].median, 0.25)

        XCTAssertEqual(Meds.highestBin(bins: bins)?.from, 1)
        let lucky = Meds.groupByHoursSinceDose(checkins: [checkin(0.5, 0.9), checkin(1.5, 0.1), checkin(1.6, 0.2)], doses: doses, measure: speed)
        XCTAssertEqual(Meds.highestBin(bins: lucky)?.from, 1)
        XCTAssertNil(Meds.highestBin(bins: Meds.groupByHoursSinceDose(checkins: [checkin(0.5, 0.9)], doses: doses, measure: speed)))
        let tie = Meds.groupByHoursSinceDose(checkins: [checkin(0.2, 0.5), checkin(0.4, 0.5), checkin(1.2, 0.5), checkin(1.4, 0.5)], doses: doses, measure: speed)
        XCTAssertEqual(Meds.highestBin(bins: tie)?.from, 0)

        let five = [checkin(1.1, 0.5), checkin(1.2, 0.5), checkin(2.1, 0.4), checkin(2.2, 0.4), checkin(5, 0.3)]
        XCTAssertEqual(Meds.minCheckins, 6)
        XCTAssertFalse(Meds.doseTiming(checkins: five, doses: doses, measure: speed, hand: "right").ready)
        let timing = Meds.doseTiming(checkins: five + [checkin(5.5, 0.3)], doses: doses, measure: speed, hand: "right")
        XCTAssertTrue(timing.ready)
        XCTAssertEqual(timing.counted, 6)
        XCTAssertEqual(timing.best?.from, 1)
        XCTAssertEqual(Meds.doseTiming(checkins: five + [checkin(5.5, 0.3, "left")], doses: doses, measure: speed, hand: "right").counted, 5)
        XCTAssertEqual(Meds.doseTiming(checkins: five + [checkin(5.5, 0.3, "right", "finger")], doses: doses, measure: speed, inputType: "pencil").counted, 5)
        XCTAssertEqual(Meds.doseTiming(checkins: five + [checkin(5.5, 0.3, "left")], doses: doses, measure: speed).counted, 6)

        // The app's own additions. Lower is better percentiles get turned around, and main wobble frequency is dropped
        let better = Meds.betterPct(["spiral_mean_speed": 0.7, "spiral_duration": 0.7, "spiral_tremor_dominant_hz": 0.5])
        XCTAssertEqual(better["spiral_mean_speed"], 0.7)
        XCTAssertEqual(better["spiral_duration"]!, 0.3, accuracy: 1e-12)
        XCTAssertNil(better["spiral_tremor_dominant_hz"])
        for key in Meds.timingMeasures { XCTAssertNotNil(Meds.higherIsBetter[key], "\(key) has no direction") }
        for key in NTFeatures.spiralFeatureOrder where key != "spiral_tremor_dominant_hz" {
            XCTAssertNotNil(Meds.higherIsBetter[key], "\(key) has no direction")
        }

        // Saved check-ins without a result are skipped
        let record = { (ts: Int, result: Bool) in
            AssessmentRecord(id: nil, ts: ts, task: "spiral", hand: "left", ageChoice: nil, bracketChoice: nil, inputType: "pencil", deviceLabel: "",
                trials: nil, features: nil,
                result: result ? Score.Result(features: [:], bracketKey: "all", referenceN: 1, deviceMatched: true, trialsPerSession: 3, tier: 0,
                    measurePct: ["spiral_mean_speed": 0.25, "spiral_mean_deviation": 0.25], topSignals: [], score: 0.5, scorePct: 0.5) : nil)
        }
        let made = Meds.checkins([record(at(1), true), record(at(2), false)])
        XCTAssertEqual(made.count, 1)
        XCTAssertEqual(made[0], Meds.Checkin(ts: at(1), hand: "left", inputType: "pencil", measurePct: ["spiral_mean_speed": 0.25, "spiral_mean_deviation": 0.75]))

        // The chart sticks to the hand and pen or finger used most, so one check-in with the other hand doesn't switch it
        let drawn = { (ts: Int, hand: String, input: String) in
            AssessmentRecord(id: nil, ts: ts, task: "spiral", hand: hand, ageChoice: nil, bracketChoice: nil, inputType: input, deviceLabel: "",
                trials: nil, features: nil, result: nil)
        }
        let most = Meds.mainSetup([drawn(at(5), "left", "pencil"), drawn(at(4), "right", "pencil"), drawn(at(3), "right", "pencil")])
        XCTAssertEqual(most?.hand, "right")
        XCTAssertEqual(most?.inputType, "pencil")
        let tied = Meds.mainSetup([drawn(at(5), "left", "touch"), drawn(at(4), "right", "pencil")])
        XCTAssertEqual(tied?.hand, "left")
        XCTAssertEqual(tied?.inputType, "touch")
        XCTAssertNil(Meds.mainSetup([]))

        print("MEDS OK")
    }

    func testDoseStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("neurotrace-doses-\(UUID().uuidString)")
        let saved = Store.folder
        Store.folder = folder
        defer {
            try? FileManager.default.removeItem(at: folder)
            Store.folder = saved
        }

        let first = try await Store.saveDose(Dose(ts: 5_000))
        let second = try await Store.saveDose(Dose(ts: 9_000))
        // logged afterward, for an earlier time
        _ = try await Store.saveDose(Dose(ts: 7_000))
        var listed = try await Store.listDoses()
        XCTAssertEqual(listed.map { d in d.ts }, [9_000, 7_000, 5_000])
        try await Store.deleteDose(second)
        listed = try await Store.listDoses()
        XCTAssertEqual(listed.map { d in d.ts }, [7_000, 5_000])
        XCTAssertEqual(listed.last?.id, first)

        let suite = "neurotrace-medication-check-\(UUID().uuidString)"
        let savedDefaults = Store.defaults
        Store.defaults = UserDefaults(suiteName: suite)!
        defer {
            Store.defaults.removePersistentDomain(forName: suite)
            Store.defaults = savedDefaults
        }
        XCTAssertEqual(Store.getMedication(), Store.Medication())
        Store.setMedication(Store.Medication(name: "Levodopa", schedule: "1 tablet at 8 AM"))
        XCTAssertEqual(Store.getMedication().name, "Levodopa")

        print("DOSE STORE OK")
    }
}
