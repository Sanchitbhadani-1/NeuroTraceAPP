// DOCTORSUMMARY.SWIFT BUILDS THE TEXT AND TABLES OF THE SUMMARY FOR A DOCTOR'S VISIT
// IT COVERS SPIRALS, BOTH HANDS, FINGER TAPPING, MEDICATION AND PRACTICE, AND SUMMARYPDF DRAWS IT

import Foundation

// Builds the doctor summary
enum DoctorSummary {

    // One section of the summary, with a title, lines of text, a table and a note
    struct Section: Equatable {
        var title: String
        var lines: [String] = []

        // The rows of the table, with the header as the first row
        var table: [[String]] = []

        // Small gray text at the end of the section
        var note: String? = nil
    }

    // The whole summary, with its title, the date it was made, its sections and the footer
    struct Document: Equatable {
        var title: String
        var made: String
        var sections: [Section]
        var footer: String
    }

    // Everything the summary is built from
    struct Input {

        // The spiral check ins, newest first
        var records: [AssessmentRecord]

        // The scoring model and the reference group
        var model: Score.Model?
        var reference: Score.Reference?

        // The finger tapping tests, oldest first
        var tapTests: [TapTest]

        // The logged doses, newest first
        var doses: [Dose]

        // The medicine name and schedule
        var medication: Store.Medication

        // The practice tries, newest first
        var tries: [TrainingTry]

        // The level reached in each exercise
        var levels: [String: Train.LevelState]

        // The time right now and the calendar used for dates
        var now: Date
        var calendar: Calendar = .current
    }

    // How many spiral rows and tapping rows the tables show, and how many days count as recent
    static let rowsShown = 12
    static let tapRowsShown = 10
    static let recentDays = 30

    // The words shown for each hand and each kind of input
    private static let handNames = ["left": "Left", "right": "Right"]
    private static let inputNames = ["pencil": "Apple Pencil", "touch": "Finger", "mouse": "Mouse"]
    private static let inputPhrases = ["pencil": "an Apple Pencil", "touch": "a finger", "mouse": "a mouse"]

    // The phrase for an input type, or "the same pen or finger" if there is none
    private static func inputPhrase(_ inputType: String?) -> String { inputType.flatMap { i in inputPhrases[i] } ?? "the same pen or finger" }

    // Make a US English date formatter in the calendar's time zone from a template
    private static func formatter(_ calendar: Calendar, _ template: String) -> DateFormatter {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.timeZone = calendar.timeZone
        format.setLocalizedDateFormatFromTemplate(template)
        return format
    }

    // Turn a time in milliseconds into a date with the month, day and year
    static func day(_ ts: Int, _ calendar: Calendar) -> String {
        formatter(calendar, "MMMdyyyy").string(from: Date(timeIntervalSince1970: Double(ts) / 1000))
    }

    // Turn a date into text like 2026-10-22 for the file name
    static func fileDate(_ date: Date, _ calendar: Calendar = .current) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = calendar.timeZone
        format.dateFormat = "yyyy-MM-dd"
        return format.string(from: date)
    }

    // Turn a fraction into a rounded percent, or a dash if it isn't a real number
    private static func percent(_ frac: Double) -> String { frac.isFinite ? "\(Int(jsRound(frac * 100)))%" : "–" }

    // Turn a fraction into a rounded percent with a plus or minus sign, or a dash if it isn't a real number
    private static func signedPercent(_ frac: Double) -> String {
        guard frac.isFinite else { return "–" }
        let p = Int(jsRound(frac * 100))
        return p > 0 ? "+\(p)%" : p < 0 ? "−\(-p)%" : "0%"
    }

    // Score a check in against one reference group and give back its measure percents
    private static func place(_ rec: AssessmentRecord, _ bracket: String?, _ input: Input) -> [String: Double] {

        // Without the model, the reference group or the features, give back the saved percents
        guard let model = input.model, let reference = input.reference, let features = rec.features ?? rec.result?.features else {
            return rec.result?.measurePct ?? [:]
        }
        return Score.scoreSession([features], model, reference, bracket).measurePct
    }

    // Build the whole summary
    static func build(_ input: Input) -> Document {

        // Start with the section about what the summary is
        var sections = [Section(title: "About this summary", lines: [
            "NeuroTrace made this summary from tests done on an iPad: drawing a spiral, tapping fingers in front of the camera, " +
                "and logging medication.",
            "These are measurements, not a diagnosis. Sleep, caffeine, stress, cold hands and medication timing can all change them " +
                "from one day to the next.",
        ])]

        // Add each section, leaving out the ones that have nothing to show
        sections.append(spirals(input))
        if let section = firstAndLatest(input) { sections.append(section) }
        if let section = hands(input) { sections.append(section) }
        sections.append(tapping(input))
        sections.append(medication(input))
        sections.append(practice(input))

        // Put the title, the date made, the sections and the footer together
        return Document(
            title: "NeuroTrace summary",
            made: "Made on \(day(Int(input.now.timeIntervalSince1970 * 1000), input.calendar))",
            sections: sections,
            footer: "NeuroTrace summary · Measurements, not a diagnosis"
        )
    }

    // The section that lists the spiral check ins
    private static func spirals(_ input: Input) -> Section {

        // Say there are no check ins if the list is empty
        let records = input.records, cal = input.calendar
        guard let latest = records.first, let oldest = records.last else {
            return Section(title: "Spiral check-ins", lines: ["No spiral check-ins yet."])
        }

        // Say how many check ins there are and the dates they cover
        var lines = [records.count == 1 ? "1 check-in, on \(day(latest.ts, cal))." : "\(records.count) check-ins from \(day(oldest.ts, cal)) to \(day(latest.ts, cal))."]

        // Say which hand and input most were drawn with, when there is more than one
        if let setup = Meds.mainSetup(records), records.count > 1 {
            lines.append("Most were drawn with the \(setup.hand) hand, using \(inputPhrase(setup.inputType)).")
        }

        // One row per recent check in, with a dash for anything missing
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

        // Say the table only shows the most recent ones when there are more
        if records.count > rowsShown { lines.append("The table shows the \(rowsShown) most recent.") }

        // Put the lines, the table and the note about what the columns mean together
        return Section(title: "Spiral check-ins", lines: lines, table: table, note:
            "Combined result is the share of the healthy adults in the reference group whose combined result was lower. " +
            "For healthy adults it spreads evenly from 0% to 100%, so 1 in 4 of them is above 75% and 1 in 20 is above 95%. " +
            "Raised it most is the measure that pushed the combined result up the most, or a dash if none did. " +
            "\(Copy.modelDisclaimer)")
    }

    // The section that compares the first and latest check in drawn with the most used hand and input
    private static func firstAndLatest(_ input: Input) -> Section? {

        // Keep only the check ins with the most used hand and input, and stop if there are fewer than two
        let cal = input.calendar
        guard let setup = Meds.mainSetup(input.records) else { return nil }
        let same = input.records.filter { r in r.hand == setup.hand && r.inputType == setup.inputType }
        guard same.count >= 2, let latest = same.first, let first = same.last else { return nil }

        // Score both against the newest check in's reference group
        let bracket = input.records.first?.bracketChoice
        let a = place(first, bracket, input), b = place(latest, bracket, input)

        // One row per measure that both check ins have a real number for
        var table = [["Measure", "First, \(day(first.ts, cal))", "Latest, \(day(latest.ts, cal))"]]
        for k in NTFeatures.spiralFeatureOrder {
            guard let x = a[k], let y = b[k], x.isFinite, y.isFinite else { continue }
            table.append([Copy.measures[k]?.name ?? k, Copy.measureShort(k, x), Copy.measureShort(k, y)])
        }

        // Leave the section out if no measure made it into the table
        if table.count < 2 { return nil }
        return Section(
            title: "First and latest check-in",
            lines: ["Both drawn with the \(latest.hand) hand, using \(inputPhrase(latest.inputType)), and compared with the same reference group."],
            table: table,
            note: "Each cell says how the measure compares with the healthy adults in the reference group."
        )
    }

    // The section that compares the latest left hand and right hand check ins
    private static func hands(_ input: Input) -> Section? {

        // Stop if there is no pair of left and right check ins
        let cal = input.calendar
        guard let pair = Hands.latestPair(input.records) else { return nil }

        // Score both hands against the newer one's reference group and compare them
        let bracket = (pair.left.ts >= pair.right.ts ? pair.left : pair.right).bracketChoice
        let rows = Hands.compareHands(left: place(pair.left, bracket, input), right: place(pair.right, bracket, input))
        if rows.isEmpty { return nil }

        // Show the first 6 measures
        var table = [["Measure", "Left hand", "Right hand"]]
        for r in rows.prefix(6) { table.append([Copy.measures[r.key]?.name ?? r.key, Copy.measureShort(r.key, r.left), Copy.measureShort(r.key, r.right)]) }
        return Section(
            title: "Left vs right hand",
            lines: ["Left hand on \(day(pair.left.ts, cal)), right hand on \(day(pair.right.ts, cal)), both using \(inputPhrase(pair.left.inputType)). Biggest differences first."],
            table: table,
            note: "Some difference between the hands is normal, especially for the hand someone doesn't write with."
        )
    }

    // The section that lists the finger tapping tests
    private static func tapping(_ input: Input) -> Section {

        // Keep the tests that counted, newest first, and say there are none if the list is empty
        let cal = input.calendar
        let tests = input.tapTests.filter { t in t.result.counted }.sorted { a, b in a.ts > b.ts }
        guard let newest = tests.first, let oldest = tests.last else {
            return Section(title: "Finger tapping", lines: ["No finger tapping tests yet."])
        }

        // Say how many tests there are and the dates they cover
        var lines = [tests.count == 1 ? "1 test, on \(day(newest.ts, cal))." : "\(tests.count) tests from \(day(oldest.ts, cal)) to \(day(newest.ts, cal))."]

        // One row per recent test, with a dash for anything missing
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

        // Say the table only shows the most recent ones when there are more
        if tests.count > tapRowsShown { lines.append("The table shows the \(tapRowsShown) most recent.") }

        // Put the lines, the table and the note about what the columns mean together
        return Section(title: "Finger tapping", lines: lines, table: table, note:
            "Thumb and index finger tapping in front of the iPad's front camera, measured with Apple's hand tracking. " +
            "Rhythm variation is how much the time between taps varied. Opening change compares how wide the last third " +
            "of the taps opened with the first third.")
    }

    // The section about the medicine and the logged doses
    private static func medication(_ input: Input) -> Section {

        // The medicine name, with the schedule when there is one
        var lines: [String] = []
        let med = input.medication
        if !med.name.isEmpty { lines.append(med.schedule.isEmpty ? med.name : "\(med.name), \(med.schedule)") }

        // Count the doses logged in the recent days
        let since = Int(input.now.timeIntervalSince1970 * 1000) - recentDays * 86_400_000
        let recent = input.doses.filter { d in d.ts >= since }.count
        lines.append(recent == 0 ? "No doses logged in the last \(recentDays) days." : "\(recent) \(recent == 1 ? "dose" : "doses") logged in the last \(recentDays) days.")

        // Say how long after a dose drawing speed was best, or that there isn't enough yet when there are doses
        if let timing = doseTiming(input), timing.ready, let best = timing.best {
            lines.append(
                "So far, drawing speed has tended to be best \(Copy.hoursAfter(best.from, best.to)) after a dose. That's from " +
                "\(best.n) check-ins in that window, out of \(timing.counted) drawn within 12 hours of a dose."
            )
        } else if !input.doses.isEmpty {
            lines.append("There aren't enough check-ins close to logged doses to show a pattern yet.")
        }

        // Put the lines and the note together
        return Section(title: "Medication", lines: lines, note:
            "The medicine, schedule and doses were entered by the person using NeuroTrace. Timing shows a pattern in drawing, " +
            "not how well a medicine works.")
    }

    // Find how drawing speed lines up with the time since a dose, for the most used hand and input
    private static func doseTiming(_ input: Input) -> Meds.Timing? {
        guard let latest = input.records.first, let setup = Meds.mainSetup(input.records) else { return nil }

        // Score every check in against the newest check in's reference group
        let checkins = Meds.checkins(input.records) { rec in place(rec, latest.bracketChoice, input) }
        return Meds.doseTiming(checkins: checkins, doses: input.doses, measure: "spiral_mean_speed", hand: setup.hand, inputType: setup.inputType)
    }

    // The section about the practice exercises
    private static func practice(_ input: Input) -> Section {

        // Say there are no exercises yet if there are no tries
        if input.tries.isEmpty { return Section(title: "Practice exercises", lines: ["No practice exercises yet."]) }
        let since = Int(input.now.timeIntervalSince1970 * 1000) - recentDays * 86_400_000

        // One row per exercise with its level and the number of recent tries
        var table = [["Exercise", "Level", "Tries in the last \(recentDays) days"]]
        for id in Practice.exercises {
            let level = (input.levels[id]?.level ?? 0) + 1, count = Train.exercises[id]?.levels.count ?? 10
            let tries = input.tries.filter { t in t.exercise == id && t.ts >= since }.count
            table.append([Copy.exerciseNames[id] ?? id, "\(level) of \(count)", String(tries)])
        }

        // Count the days practiced in the recent days and put the section together
        let days = Practice.daysPracticed(input.tries.map { t in t.ts }, days: recentDays, now: input.now, calendar: input.calendar)
        return Section(title: "Practice exercises", lines: ["Practiced on \(days) of the last \(recentDays) days."], table: table)
    }
}
