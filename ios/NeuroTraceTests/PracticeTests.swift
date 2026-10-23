// check Today's focus, the week's practice days, and the doctor summary

import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

private let dayMs = 86_400_000

private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2 // Monday
    return calendar
}

// Wednesday Oct 21 2026, 15:00 UTC
private let wednesday = Date(timeIntervalSince1970: 1_792_594_800)
private func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

private func record(_ ts: Int, _ hand: String = "right", _ input: String = "pencil", pct: [String: Double] = [:], top: [String] = [], scorePct: Double = 0.5) -> AssessmentRecord {
    AssessmentRecord(id: ts, ts: ts, task: "spiral", hand: hand, ageChoice: nil, bracketChoice: nil, inputType: input, deviceLabel: "",
        trials: nil, features: nil,
        result: Score.Result(features: [:], bracketKey: "all", referenceN: 36, deviceMatched: true, trialsPerSession: 3, tier: 0,
            measurePct: pct, topSignals: top, score: 0.5, scorePct: scorePct))
}

private func tapTest(_ ts: Int, _ hand: String, rate: Double?, counted: Bool = true) -> TapTest {
    TapTest(ts: ts, hand: hand, result: TapResult(counted: counted, taps: counted ? 10 : 2, duration: 4, rate: rate, rhythmCv: 0.12,
        meanOpening: 1, openingChange: -0.18, rateChange: 0, pauses: 1, tapTimes: [], openings: []))
}

private func practiceTry(_ ts: Int, _ exercise: String) -> TrainingTry {
    TrainingTry(id: nil, ts: ts, exercise: exercise, level: 0, target: 0.2, counted: true, hit: true, reachedTarget: true, slower: false,
        shakier: false, measures: [:], vs: Train.Vs(pace: nil, smoothness: nil), inputType: "pencil", path: nil, geometry: nil, results: nil)
}

final class PracticeTests: XCTestCase {
    func testFocusAndWeek() {
        // The measure that stood out most picks the exercise. Main wobble frequency has none, so the next one counts
        let wobbly = record(1, top: ["spiral_tremor_dominant_hz", "spiral_mean_deviation", "spiral_duration"])
        XCTAssertEqual(Practice.focus(latest: wobbly, lastPracticed: [:]), Practice.Focus(exercise: "steady-tracing", measure: "spiral_mean_deviation", checkinTs: 1))
        XCTAssertEqual(Practice.focus(latest: record(2, top: ["spiral_duration"]), lastPracticed: [:]).exercise, "big-writing")
        XCTAssertEqual(Practice.focus(latest: record(3, top: ["spiral_ldlj"]), lastPracticed: [:]).exercise, "rhythm")
        // Only a measure that pushed the combined result up counts. Here the first one pulled it down
        var mixed = record(4, top: ["spiral_duration", "spiral_ldlj"])
        mixed.result?.contributions = ["spiral_duration": -0.2, "spiral_ldlj": 0.3]
        XCTAssertEqual(Practice.focus(latest: mixed, lastPracticed: [:]), Practice.Focus(exercise: "rhythm", measure: "spiral_ldlj", checkinTs: 4))
        // A very typical drawing where every measure pulled it down, so no measure stood out
        var typical = record(5, top: ["spiral_duration", "spiral_ldlj"])
        typical.result?.contributions = ["spiral_duration": -0.2, "spiral_ldlj": -0.3]
        XCTAssertEqual(Practice.focus(latest: typical, lastPracticed: ["big-writing": 9]), Practice.Focus(exercise: "rhythm", measure: nil, checkinTs: 5))
        XCTAssertEqual(Score.pushedUp(typical.result!), [])
        // No check-in: the exercise practiced least recently, never practiced first
        XCTAssertEqual(Practice.focus(latest: nil, lastPracticed: [:]), Practice.Focus(exercise: "big-writing", measure: nil, checkinTs: nil))
        XCTAssertEqual(Practice.focus(latest: nil, lastPracticed: ["big-writing": 9, "rhythm": 5, "steady-tracing": 7, "hand-skills": 8]).exercise, "rhythm")
        XCTAssertEqual(Practice.focus(latest: nil, lastPracticed: ["big-writing": 9, "rhythm": 5]).exercise, "steady-tracing")
        // Every measure but main wobble frequency has an exercise, and every exercise is a real one
        for k in NTFeatures.spiralFeatureOrder where k != "spiral_tremor_dominant_hz" { XCTAssertNotNil(Practice.exerciseFor[k], k) }
        for ex in Practice.exerciseFor.values { XCTAssertTrue(Train.exercises[ex]?.built ?? false, ex) }

        // This week, Monday to Sunday: Monday and Wednesday practiced, Thursday on are still to come
        let cal = utc()
        let monday = ms(wednesday) - 2 * dayMs, lastSunday = ms(wednesday) - 3 * dayMs
        let week = Practice.week([monday + 3_600_000, ms(wednesday), ms(wednesday) - 60_000, lastSunday], now: wednesday, calendar: cal)
        XCTAssertEqual(week, [true, false, true, nil, nil, nil, nil])
        XCTAssertEqual(Practice.week([], now: wednesday, calendar: cal), [false, false, false, nil, nil, nil, nil])
        XCTAssertEqual(Practice.daysPracticed([monday, ms(wednesday), lastSunday, ms(wednesday) - 40 * dayMs], days: 30, now: wednesday, calendar: cal), 3)

        // The newest try of each exercise, from tries listed newest first
        let tries = [practiceTry(30, "rhythm"), practiceTry(20, "big-writing"), practiceTry(10, "rhythm")]
        XCTAssertEqual(Practice.lastPracticed(tries), ["rhythm": 30, "big-writing": 20])
        XCTAssertEqual(Practice.lastPracticed([]), [:])
        // Earlier today counts, late last night doesn't
        let midnight = ms(cal.startOfDay(for: wednesday))
        XCTAssertTrue(Practice.doneToday([midnight + 1000], now: wednesday, calendar: cal))
        XCTAssertFalse(Practice.doneToday([midnight - 1000], now: wednesday, calendar: cal))
        XCTAssertFalse(Practice.doneToday([], now: wednesday, calendar: cal))
        print("PRACTICE OK")
    }

    func testDoctorSummary() throws {
        let cal = utc()
        let now = wednesday, t = ms(wednesday)
        let older = record(t - 20 * dayMs, pct: ["spiral_duration": 0.3, "spiral_mean_speed": 0.7], top: ["spiral_duration"], scorePct: 0.41)
        let newer = record(t - dayMs, pct: ["spiral_duration": 0.8, "spiral_mean_speed": 0.2], top: ["spiral_mean_speed"], scorePct: 0.66)
        let left = record(t - 2 * dayMs, "left", pct: ["spiral_duration": 0.9, "spiral_mean_speed": 0.1], top: ["spiral_duration"], scorePct: 0.8)
        let input = DoctorSummary.Input(
            records: [newer, left, older], model: nil, reference: nil,
            tapTests: [tapTest(t - 5 * dayMs, "left", rate: 2.25), tapTest(t - 4 * dayMs, "right", rate: 3), tapTest(t - 3 * dayMs, "right", rate: nil, counted: false)],
            doses: [Dose(id: 1, ts: t - 2 * dayMs), Dose(id: 2, ts: t - 40 * dayMs)],
            medication: Store.Medication(name: "Levodopa", schedule: "1 tablet at 8 AM"),
            tries: [practiceTry(t - dayMs, "rhythm"), practiceTry(t - 3 * dayMs, "rhythm")],
            levels: ["rhythm": Train.LevelState(level: 2, hits: 1, misses: 0, last: "up")],
            now: now, calendar: cal
        )
        let doc = DoctorSummary.build(input)
        XCTAssertEqual(doc.made, "Made on Oct 21, 2026")
        let titles = doc.sections.map { s in s.title }
        XCTAssertEqual(titles, ["About this summary", "Spiral check-ins", "First and latest check-in", "Left vs right hand", "Finger tapping", "Medication", "Practice exercises"])
        let spirals = doc.sections[1]
        XCTAssertEqual(spirals.lines[0], "3 check-ins from Oct 1, 2026 to Oct 20, 2026.")
        XCTAssertEqual(spirals.lines[1], "Most were drawn with the right hand, using an Apple Pencil.")
        XCTAssertEqual(spirals.table[1], ["Oct 20, 2026", "Right", "Apple Pencil", "66%", "Average speed"])
        XCTAssertTrue(spirals.note!.contains("AUC 0.71"))
        let firstLatest = doc.sections[2]
        XCTAssertEqual(firstLatest.table[0], ["Measure", "First, Oct 1, 2026", "Latest, Oct 20, 2026"])
        XCTAssertEqual(firstLatest.table[1], ["Drawing time", "Quicker than 70%", "Took longer than 80%"])
        // One newer check-in with the other hand doesn't change which pair is compared
        var otherHandNewest = input
        otherHandNewest.records = [record(t - 12 * 3_600_000, "left", pct: ["spiral_duration": 0.5], top: [], scorePct: 0.5), newer, older]
        XCTAssertEqual(DoctorSummary.build(otherHandNewest).sections[2].table[0], ["Measure", "First, Oct 1, 2026", "Latest, Oct 20, 2026"])
        let hands = doc.sections[3]
        XCTAssertEqual(hands.table.count, 3)
        let tapping = doc.sections[4]
        XCTAssertEqual(tapping.lines[0], "2 tests from Oct 16, 2026 to Oct 17, 2026.")
        XCTAssertEqual(tapping.table[1], ["Oct 17, 2026", "Right", "3.0", "12%", "−18%", "1"])
        let meds = doc.sections[5]
        XCTAssertEqual(meds.lines[0], "Levodopa, 1 tablet at 8 AM")
        XCTAssertEqual(meds.lines[1], "1 dose logged in the last 30 days.")
        let practice = doc.sections[6]
        XCTAssertEqual(practice.lines, ["Practiced on 2 of the last 30 days."])
        XCTAssertEqual(practice.table[2], ["Rhythm", "3 of 10", "2"])
        // Nothing reads NaN or nil anywhere
        let everything = doc.sections.flatMap { s in s.lines + s.table.flatMap { r in r } + [s.note ?? ""] }.joined(separator: " ")
        for bad in ["nan", "NaN", "nil", "Optional", "inf"] { XCTAssertFalse(everything.contains(bad), "\(bad) in the summary") }

        // An empty device still makes a sensible summary
        let empty = DoctorSummary.build(DoctorSummary.Input(records: [], model: nil, reference: nil, tapTests: [], doses: [], medication: Store.Medication(),
            tries: [], levels: [:], now: now, calendar: cal))
        XCTAssertEqual(empty.sections.map { s in s.title }, ["About this summary", "Spiral check-ins", "Finger tapping", "Medication", "Practice exercises"])
        XCTAssertEqual(empty.sections[1].lines, ["No spiral check-ins yet."])
        XCTAssertEqual(DoctorSummary.fileDate(now, cal), "2026-10-21")

        // Six check-ins near a dose give the best window, how many check-ins it has, and how many there are in all
        let hour = 3_600_000
        let doseTimes = [t - 3 * dayMs, t - 2 * dayMs, t - dayMs]
        let nearDoses = doseTimes.flatMap { d in
            [record(d + 3 * hour / 2, pct: ["spiral_mean_speed": 0.8]), record(d + 5 * hour, pct: ["spiral_mean_speed": 0.4])]
        }.sorted { a, b in a.ts > b.ts }
        var timed = input
        timed.records = nearDoses
        timed.doses = doseTimes.reversed().enumerated().map { (i, d) in Dose(id: i + 1, ts: d) }
        let medLines = DoctorSummary.build(timed).sections.first { s in s.title == "Medication" }!.lines
        XCTAssertEqual(medLines.last, "So far, drawing speed has tended to be best 1 to 2 hours after a dose. That's from 3 check-ins in that window, out of 6 drawn within 12 hours of a dose.")

        // With the real model files, check-ins are placed against the newest one's reference group
        let resources = repoRoot.appendingPathComponent("ios/NeuroTrace/Resources")
        let model = try JSONDecoder().decode(Score.Model.self, from: Data(contentsOf: resources.appendingPathComponent("model.json")))
        let reference = try JSONDecoder().decode(Score.Reference.self, from: Data(contentsOf: resources.appendingPathComponent("reference.json")))
        var withFeatures = input
        let features = Dictionary(uniqueKeysWithValues: model.featureOrder.map { k in (k, reference.brackets["all"]!.mean[model.featureOrder.firstIndex(of: k)!]) })
        withFeatures.records = withFeatures.records.map { r in var copy = r; copy.features = features; return copy }
        withFeatures.model = model
        withFeatures.reference = reference
        let placed = DoctorSummary.build(withFeatures)
        XCTAssertEqual(placed.sections[2].table.count, 1 + model.featureOrder.count, "every measure compared")
        print("DOCTOR SUMMARY OK")
    }

    func testClearPersonalData() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("neurotrace-clear-\(UUID().uuidString)")
        let exports = folder.appendingPathComponent("exports", isDirectory: true)
        let savedFolder = Store.folder, savedDefaults = Store.defaults, savedExports = Store.exportsFolder
        let suite = "neurotrace-clear-check-\(UUID().uuidString)"
        Store.folder = folder
        Store.defaults = UserDefaults(suiteName: suite)!
        Store.exportsFolder = exports
        defer {
            try? FileManager.default.removeItem(at: folder)
            Store.defaults.removePersistentDomain(forName: suite)
            Store.folder = savedFolder
            Store.defaults = savedDefaults
            Store.exportsFolder = savedExports
        }
        _ = try await Store.saveAssessment(record(1))
        _ = try await Store.saveTrainingTry(practiceTry(2, "rhythm"))
        Store.setTrainingState("rhythm", Train.LevelState(level: 1, hits: 0, misses: 0, last: nil))
        _ = try await Store.saveDose(Dose(ts: 3))
        Store.setMedication(Store.Medication(name: "Levodopa", schedule: ""))
        Store.saveTapTest(tapTest(4, "left", rate: 2))
        Store.setHomeScans([HomeScan(ts: 5, room: "Room", ideas: [])])
        Store.defaults.set(true, forKey: Store.homeScanConsentKey)
        Store.setPrefs { p in
            p.theme = "dark"
            p.ageChoice = "60\u{2013}69"
            p.hand = "left"
        }
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        try Data("summary".utf8).write(to: exports.appendingPathComponent("NeuroTrace summary.pdf"))

        try await Store.clearPersonalData()
        let assessments = try await Store.listAssessments(), tries = try await Store.listTrainingTries()
        XCTAssertEqual(assessments, [])
        XCTAssertEqual(tries, [])
        XCTAssertNil(Store.getTrainingState("rhythm"))
        let doses = try await Store.listDoses()
        XCTAssertEqual(doses, [])
        XCTAssertEqual(Store.getMedication(), Store.Medication())
        XCTAssertEqual(Store.getTapTests(), [])
        XCTAssertEqual(Store.getHomeScans(), [])
        XCTAssertFalse(Store.defaults.bool(forKey: Store.homeScanConsentKey))
        // The age group and drawing hand go back to how a new install starts, and the last export is gone
        XCTAssertNil(Store.getPrefs().ageChoice)
        XCTAssertEqual(Store.getPrefs().hand, Store.prefsDefaults.hand)
        XCTAssertFalse(FileManager.default.fileExists(atPath: exports.path))
        // The app's own settings stay
        XCTAssertEqual(Store.getPrefs().theme, "dark")
        print("CLEAR OK")
    }
}
