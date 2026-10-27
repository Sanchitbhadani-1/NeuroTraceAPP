// DEMODATATESTS.SWIFT CHECKS THE SAMPLE DATA
// IT CHECKS THAT EVERY MADE UP SPIRAL PASSES THE SPIRAL CHECK, THE SCREENS THAT NEED HISTORY GET ENOUGH, AND LOADING IT FILLS THE STORE

import Foundation
import XCTest
// Use the NeuroTraceCore module when it exists, or the app if it doesn't
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

// The tests for the sample data
final class DemoDataTests: XCTestCase {

    // Check that the sample data is complete and loads into the store
    func testSampleData() async throws {

        // Load the scoring files and make the sample data for a fixed time in New York
        let resources = repoRoot.appendingPathComponent("ios/NeuroTrace/Resources")
        let model = try JSONDecoder().decode(Score.Model.self, from: Data(contentsOf: resources.appendingPathComponent("model.json")))
        let reference = try JSONDecoder().decode(Score.Reference.self, from: Data(contentsOf: resources.appendingPathComponent("reference.json")))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = Date(timeIntervalSince1970: 1_792_800_000)
        let made = try DemoData.make(model: model, reference: reference, now: now, calendar: calendar)

        // Check that the check ins are oldest first, the newest is the right hand, and each has three spirals that pass the spiral check
        XCTAssertEqual(made.records.count, DemoData.rightCheckins.count + DemoData.leftCheckins.count)
        XCTAssertEqual(made.records.map { r in r.ts }, made.records.map { r in r.ts }.sorted(), "oldest first")
        XCTAssertEqual(made.records.last?.hand, "right", "the newest check-in is the main hand")
        for r in made.records {
            XCTAssertEqual(r.trials?.count, 3)
            for t in r.trials ?? [] { XCTAssertNil(SpiralCheck.problem(t.features), "a sample spiral wouldn't pass the spiral check") }
            XCTAssertNotNil(r.result)
        }

        // Print each check in's hand and score
        print("sample combined results", made.records.map { r in "\(r.hand.prefix(1))\(Int(((r.result?.scorePct ?? 0) * 100).rounded()))%" })

        // Check that the medication chart is ready and its best time is one to two hours after a dose
        let timing = Meds.doseTiming(checkins: Meds.checkins(made.records), doses: made.doses, measure: "spiral_mean_speed", hand: "right", inputType: "pencil")
        XCTAssertTrue(timing.ready)
        XCTAssertEqual(timing.best?.from, 1)

        // Print each time group with its count and middle value
        print("sample timing", timing.bins.map { b in "\(b.from)-\(b.to)h n=\(b.n) \(b.median.map { m in Int((m * 100).rounded()) } ?? -1)%" })

        // Check that there is a left and right hand check in close enough to compare
        XCTAssertNotNil(Hands.latestPair(made.records))

        // Check that every tapping test counts and has at least 9 taps
        for t in made.taps {
            XCTAssertTrue(t.result.counted, "\(t.hand) tapping test didn't count")
            XCTAssertGreaterThanOrEqual(t.result.taps, 9)
        }

        // Print each tapping test's hand, taps and taps per second
        print("sample tapping", made.taps.map { t in "\(t.hand) \(t.result.taps) taps \(String(format: "%.1f", t.result.rate ?? 0))/s" })

        // Check that there is practice on four exercises, four levels are set, and no doses are in the future
        XCTAssertEqual(Set(made.tries.map { t in t.exercise }).count, 4)
        XCTAssertEqual(made.levels.count, 4)
        XCTAssertTrue(made.doses.allSatisfy { d in d.ts <= Int(now.timeIntervalSince1970 * 1000) })

        // Check that making the sample data again gives the same measurements
        let again = try DemoData.make(model: model, reference: reference, now: now, calendar: calendar)
        XCTAssertEqual(again.records.map { r in r.features ?? [:] }, made.records.map { r in r.features ?? [:] })

        // Point the store at an empty test folder and settings, and put the real ones back at the end
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("neurotrace-sample-\(UUID().uuidString)")
        let savedFolder = Store.folder, savedDefaults = Store.defaults
        let suite = "neurotrace-sample-check-\(UUID().uuidString)"
        Store.folder = folder
        Store.defaults = UserDefaults(suiteName: suite)!
        defer {
            try? FileManager.default.removeItem(at: folder)
            Store.defaults.removePersistentDomain(forName: suite)
            Store.folder = savedFolder
            Store.defaults = savedDefaults
        }

        // Save one dose, then load the sample data
        _ = try await Store.saveDose(Dose(ts: 1))
        try await DemoData.load(model: model, reference: reference, now: now, calendar: calendar)

        // Check that the store now holds exactly the sample data, with the old dose gone
        let records = try await Store.listAssessments(), doses = try await Store.listDoses(), tries = try await Store.listTrainingTries()
        XCTAssertEqual(records.count, made.records.count)
        XCTAssertEqual(doses.count, made.doses.count, "the old dose is gone")
        XCTAssertEqual(tries.count, made.tries.count)
        XCTAssertEqual(Store.getTapTests().count, made.taps.count)

        // Check that only the newest check ins keep their full drawing, and the medicine, age and level are set
        XCTAssertEqual(records.filter { r in r.trials?.first?.samples != nil }.count, Store.rawKeep, "only the newest keep their full drawing")
        XCTAssertEqual(Store.getMedication(), DemoData.medication)
        XCTAssertEqual(Store.getPrefs().ageChoice, DemoData.ageChoice)
        XCTAssertEqual(Store.getTrainingState("big-writing")?.level, 2)
        print("SAMPLE DATA OK")
    }
}
