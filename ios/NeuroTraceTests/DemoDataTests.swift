// check the sample data. Every made up spiral passes the spiral check, the screens that need history get
// enough of it, and loading it fills the store

import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

final class DemoDataTests: XCTestCase {
    func testSampleData() async throws {
        let resources = repoRoot.appendingPathComponent("ios/NeuroTrace/Resources")
        let model = try JSONDecoder().decode(Score.Model.self, from: Data(contentsOf: resources.appendingPathComponent("model.json")))
        let reference = try JSONDecoder().decode(Score.Reference.self, from: Data(contentsOf: resources.appendingPathComponent("reference.json")))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let now = Date(timeIntervalSince1970: 1_792_800_000)
        let made = try DemoData.make(model: model, reference: reference, now: now, calendar: calendar)

        // Check-ins have three spirals each, all of them good enough to count
        XCTAssertEqual(made.records.count, DemoData.rightCheckins.count + DemoData.leftCheckins.count)
        XCTAssertEqual(made.records.map { r in r.ts }, made.records.map { r in r.ts }.sorted(), "oldest first")
        XCTAssertEqual(made.records.last?.hand, "right", "the newest check-in is the main hand")
        for r in made.records {
            XCTAssertEqual(r.trials?.count, 3)
            for t in r.trials ?? [] { XCTAssertNil(SpiralCheck.problem(t.features), "a sample spiral wouldn't pass the spiral check") }
            XCTAssertNotNil(r.result)
        }
        print("sample combined results", made.records.map { r in "\(r.hand.prefix(1))\(Int(((r.result?.scorePct ?? 0) * 100).rounded()))%" })

        // The medication chart has enough check-ins, and they're best one to two hours after a dose
        let timing = Meds.doseTiming(checkins: Meds.checkins(made.records), doses: made.doses, measure: "spiral_mean_speed", hand: "right", inputType: "pencil")
        XCTAssertTrue(timing.ready)
        XCTAssertEqual(timing.best?.from, 1)
        print("sample timing", timing.bins.map { b in "\(b.from)-\(b.to)h n=\(b.n) \(b.median.map { m in Int((m * 100).rounded()) } ?? -1)%" })

        // A left and a right hand check-in within a week, for the hand comparison
        XCTAssertNotNil(Hands.latestPair(made.records))

        // Every tapping test counts, with all ten taps
        for t in made.taps {
            XCTAssertTrue(t.result.counted, "\(t.hand) tapping test didn't count")
            XCTAssertGreaterThanOrEqual(t.result.taps, 9)
        }
        print("sample tapping", made.taps.map { t in "\(t.hand) \(t.result.taps) taps \(String(format: "%.1f", t.result.rate ?? 0))/s" })

        // Practice on four exercises, levels set, no doses in the future
        XCTAssertEqual(Set(made.tries.map { t in t.exercise }).count, 4)
        XCTAssertEqual(made.levels.count, 4)
        XCTAssertTrue(made.doses.allSatisfy { d in d.ts <= Int(now.timeIntervalSince1970 * 1000) })

        // The same every time
        let again = try DemoData.make(model: model, reference: reference, now: now, calendar: calendar)
        XCTAssertEqual(again.records.map { r in r.features ?? [:] }, made.records.map { r in r.features ?? [:] })

        // Loading replaces the store's data with it
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
        _ = try await Store.saveDose(Dose(ts: 1))
        try await DemoData.load(model: model, reference: reference, now: now, calendar: calendar)
        let records = try await Store.listAssessments(), doses = try await Store.listDoses(), tries = try await Store.listTrainingTries()
        XCTAssertEqual(records.count, made.records.count)
        XCTAssertEqual(doses.count, made.doses.count, "the old dose is gone")
        XCTAssertEqual(tries.count, made.tries.count)
        XCTAssertEqual(Store.getTapTests().count, made.taps.count)
        XCTAssertEqual(records.filter { r in r.trials?.first?.samples != nil }.count, Store.rawKeep, "only the newest keep their full drawing")
        XCTAssertEqual(Store.getMedication(), DemoData.medication)
        XCTAssertEqual(Store.getPrefs().ageChoice, DemoData.ageChoice)
        XCTAssertEqual(Store.getTrainingState("big-writing")?.level, 2)
        print("SAMPLE DATA OK")
    }
}
