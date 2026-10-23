import Foundation

// The summary for a doctor's visit: what goes in it, as text and tables. SummaryPDF draws it.
// No screen code here, so the tests can check what it says

enum DoctorSummary {
    struct Section: Equatable {
        var title: String
        var lines: [String] = []
        // The first row is the header
        var table: [[String]] = []
        // Small gray text at the end of the section
        var note: String? = nil
    }

    struct Document: Equatable {
        var title: String
        var made: String
        var sections: [Section]
        var footer: String
    }

    struct Input {
        // Newest first, the way Store lists them
        var records: [AssessmentRecord]
        var model: Score.Model?
        var reference: Score.Reference?
        // Oldest first, the way Store keeps them
        var tapTests: [TapTest]
        // Newest first
        var doses: [Dose]
        var medication: Store.Medication
        // Newest first
        var tries: [TrainingTry]
        var levels: [String: Train.LevelState]
        var now: Date
        var calendar: Calendar = .current
    }

    static let rowsShown = 12
    static let tapRowsShown = 10
    static let recentDays = 30

    private static let handNames = ["left": "Left", "right": "Right"]
    private static let inputNames = ["pencil": "Apple Pencil", "touch": "Finger", "mouse": "Mouse"]
    private static let inputPhrases = ["pencil": "an Apple Pencil", "touch": "a finger", "mouse": "a mouse"]

    private static func inputPhrase(_ inputType: String?) -> String { inputType.flatMap { i in inputPhrases[i] } ?? "the same pen or finger" }

    private static func formatter(_ calendar: Calendar, _ template: String) -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = calendar.timeZone
        format.setLocalizedDateFormatFromTemplate(template)
        return format
    }

    static func day(_ ts: Int, _ calendar: Calendar) -> String {
        formatter(calendar, "MMMdyyyy").string(from: Date(timeIntervalSince1970: Double(ts) / 1000))
    }

    // For the file name, like 2026-10-22
    static func fileDate(_ date: Date, _ calendar: Calendar = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = calendar.timeZone
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }

    private static func percent(_ frac: Double) -> String { frac.isFinite ? "\(Int(jsRound(frac * 100)))%" : "–" }

    private static func signedPercent(_ frac: Double) -> String {
        guard frac.isFinite else { return "–" }
        let p = Int(jsRound(frac * 100))
        return p > 0 ? "+\(p)%" : p < 0 ? "−\(-p)%" : "0%"
    }

    // A check-in placed against one reference group, so two check-ins compare fairly
    private static func place(_ rec: AssessmentRecord, _ bracket: String?, _ input: Input) -> [String: Double] {
        guard let model = input.model, let reference = input.reference, let features = rec.features ?? rec.result?.features else {
            return rec.result?.measurePct ?? [:]
        }
        return Score.scoreSession([features], model, reference, bracket).measurePct
    }

    static func build(_ input: Input) -> Document {
        var sections = [Section(title: "About this summary", lines: [
            "NeuroTrace made this summary from tests done on an iPad: drawing a spiral, tapping fingers in front of the camera, " +
                "and logging medication.",
            "These are measurements, not a diagnosis. Sleep, caffeine, stress, cold hands and medication timing can all change them " +
                "from one day to the next.",
        ])]
        sections.append(spirals(input))
        if let section = firstAndLatest(input) { sections.append(section) }
        if let section = hands(input) { sections.append(section) }
        sections.append(tapping(input))
        sections.append(medication(input))
        sections.append(practice(input))
        return Document(
            title: "NeuroTrace summary",
            made: "Made on \(day(Int(input.now.timeIntervalSince1970 * 1000), input.calendar))",
            sections: sections,
            footer: "NeuroTrace summary · Measurements, not a diagnosis"
        )
    }

    private static func spirals(_ input: Input) -> Section {
        let records = input.records, cal = input.calendar
        guard let latest = records.first, let oldest = records.last else {
            return Section(title: "Spiral check-ins", lines: ["No spiral check-ins yet."])
        }
        var lines = [records.count == 1 ? "1 check-in, on \(day(latest.ts, cal))." : "\(records.count) check-ins from \(day(oldest.ts, cal)) to \(day(latest.ts, cal))."]
        if let setup = Meds.mainSetup(records), records.count > 1 {
            lines.append("Most were drawn with the \(setup.hand) hand, using \(inputPhrase(setup.inputType)).")
        }
        var table = [["Date", "Hand", "Pen or finger", "Combined result", "Raised it most"]]
        for r in records.prefix(rowsShown) {
            table.append([
                day(r.ts, cal),
                handNames[r.hand] ?? r.hand,
                inputNames[r.inputType ?? ""] ?? "–",
                r.result.map { res in percent(res.scorePct) } ?? "–",
                r.result.flatMap { res in Score.pushedUp(res).first }.map { k in Copy.measures[k]?.name ?? k } ?? "–",
            ])
        }
        if records.count > rowsShown { lines.append("The table shows the \(rowsShown) most recent.") }
        return Section(title: "Spiral check-ins", lines: lines, table: table, note:
            "Combined result is the share of the healthy adults in the reference group whose combined result was lower. " +
            "For healthy adults it spreads evenly from 0% to 100%, so 1 in 4 of them is above 75% and 1 in 20 is above 95%. " +
            "Raised it most is the measure that pushed the combined result up the most, or a dash if none did. " +
            "\(Copy.modelDisclaimer)")
    }

    // The first and latest check-in drawn the way most were, the same pair the Progress tab shows
    private static func firstAndLatest(_ input: Input) -> Section? {
        let cal = input.calendar
        guard let setup = Meds.mainSetup(input.records) else { return nil }
        let same = input.records.filter { r in r.hand == setup.hand && r.inputType == setup.inputType }
        guard same.count >= 2, let latest = same.first, let first = same.last else { return nil }
        let bracket = input.records.first?.bracketChoice
        let a = place(first, bracket, input), b = place(latest, bracket, input)
        var table = [["Measure", "First, \(day(first.ts, cal))", "Latest, \(day(latest.ts, cal))"]]
        for k in NTFeatures.spiralFeatureOrder {
            guard let x = a[k], let y = b[k], x.isFinite, y.isFinite else { continue }
            table.append([Copy.measures[k]?.name ?? k, Copy.measureShort(k, x), Copy.measureShort(k, y)])
        }
        if table.count < 2 { return nil }
        return Section(
            title: "First and latest check-in",
            lines: ["Both drawn with the \(latest.hand) hand, using \(inputPhrase(latest.inputType)), and compared with the same reference group."],
            table: table,
            note: "Each cell says how the measure compares with the healthy adults in the reference group."
        )
    }

    private static func hands(_ input: Input) -> Section? {
        let cal = input.calendar
        guard let pair = Hands.latestPair(input.records) else { return nil }
        let bracket = (pair.left.ts >= pair.right.ts ? pair.left : pair.right).bracketChoice
        let rows = Hands.compareHands(left: place(pair.left, bracket, input), right: place(pair.right, bracket, input))
        if rows.isEmpty { return nil }
        var table = [["Measure", "Left hand", "Right hand"]]
        for r in rows.prefix(6) { table.append([Copy.measures[r.key]?.name ?? r.key, Copy.measureShort(r.key, r.left), Copy.measureShort(r.key, r.right)]) }
        return Section(
            title: "Left vs right hand",
            lines: ["Left hand on \(day(pair.left.ts, cal)), right hand on \(day(pair.right.ts, cal)), both using \(inputPhrase(pair.left.inputType)). Biggest differences first."],
            table: table,
            note: "Some difference between the hands is normal, especially for the hand someone doesn't write with."
        )
    }

    private static func tapping(_ input: Input) -> Section {
        let cal = input.calendar
        let tests = input.tapTests.filter { t in t.result.counted }.sorted { a, b in a.ts > b.ts }
        guard let newest = tests.first, let oldest = tests.last else {
            return Section(title: "Finger tapping", lines: ["No finger tapping tests yet."])
        }
        var lines = [tests.count == 1 ? "1 test, on \(day(newest.ts, cal))." : "\(tests.count) tests from \(day(oldest.ts, cal)) to \(day(newest.ts, cal))."]
        var table = [["Date", "Hand", "Taps per second", "Rhythm variation", "Opening change", "Pauses"]]
        for t in tests.prefix(tapRowsShown) {
            let r = t.result
            table.append([
                day(t.ts, cal),
                handNames[t.hand] ?? t.hand,
                r.rate.map { v in String(format: "%.1f", v) } ?? "–",
                r.rhythmCv.map { v in percent(v) } ?? "–",
                r.openingChange.map { v in signedPercent(v) } ?? "–",
                String(r.pauses),
            ])
        }
        if tests.count > tapRowsShown { lines.append("The table shows the \(tapRowsShown) most recent.") }
        return Section(title: "Finger tapping", lines: lines, table: table, note:
            "Thumb and index finger tapping in front of the iPad's front camera, measured with Apple's hand tracking. " +
            "Rhythm variation is how much the time between taps varied. Opening change compares how wide the last third " +
            "of the taps opened with the first third.")
    }

    private static func medication(_ input: Input) -> Section {
        var lines: [String] = []
        let med = input.medication
        if !med.name.isEmpty { lines.append(med.schedule.isEmpty ? med.name : "\(med.name), \(med.schedule)") }
        let since = Int(input.now.timeIntervalSince1970 * 1000) - recentDays * 86_400_000
        let recent = input.doses.filter { d in d.ts >= since }.count
        lines.append(recent == 0 ? "No doses logged in the last \(recentDays) days." : "\(recent) \(recent == 1 ? "dose" : "doses") logged in the last \(recentDays) days.")
        if let timing = doseTiming(input), timing.ready, let best = timing.best {
            lines.append(
                "So far, drawing speed has tended to be best \(Copy.hoursAfter(best.from, best.to)) after a dose. That's from " +
                "\(best.n) check-ins in that window, out of \(timing.counted) drawn within 12 hours of a dose."
            )
        } else if !input.doses.isEmpty {
            lines.append("There aren't enough check-ins close to logged doses to show a pattern yet.")
        }
        return Section(title: "Medication", lines: lines, note:
            "The medicine, schedule and doses were entered by the person using NeuroTrace. Timing shows a pattern in drawing, " +
            "not how well a medicine works.")
    }

    private static func doseTiming(_ input: Input) -> Meds.Timing? {
        guard let latest = input.records.first, let setup = Meds.mainSetup(input.records) else { return nil }
        let checkins = Meds.checkins(input.records) { rec in place(rec, latest.bracketChoice, input) }
        return Meds.doseTiming(checkins: checkins, doses: input.doses, measure: "spiral_mean_speed", hand: setup.hand, inputType: setup.inputType)
    }

    private static func practice(_ input: Input) -> Section {
        if input.tries.isEmpty { return Section(title: "Practice exercises", lines: ["No practice exercises yet."]) }
        let since = Int(input.now.timeIntervalSince1970 * 1000) - recentDays * 86_400_000
        var table = [["Exercise", "Level", "Tries in the last \(recentDays) days"]]
        for id in Practice.exercises {
            let level = (input.levels[id]?.level ?? 0) + 1, count = Train.exercises[id]?.levels.count ?? 10
            let tries = input.tries.filter { t in t.exercise == id && t.ts >= since }.count
            table.append([Copy.exerciseNames[id] ?? id, "\(level) of \(count)", String(tries)])
        }
        let days = Practice.daysPracticed(input.tries.map { t in t.ts }, days: recentDays, now: input.now, calendar: input.calendar)
        return Section(title: "Practice exercises", lines: ["Practiced on \(days) of the last \(recentDays) days."], table: table)
    }
}
