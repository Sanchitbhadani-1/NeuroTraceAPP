// DEMODATA.SWIFT MAKES UP ABOUT THREE WEEKS OF SAMPLE DATA FOR DEMO VIDEOS
// IT MAKES CHECK INS, DOSES, PRACTICE AND FINGER TAPPING, AND MEASURES AND SCORES THEM WITH THE SAME JAVASCRIPT AS REAL ONES

import Foundation

// Makes the sample data and saves it on the device
enum DemoData {

    // Everything that gets made
    struct Made {
        var records: [AssessmentRecord]
        var doses: [Dose]
        var tries: [TrainingTry]
        var levels: [String: Train.LevelState]
        var taps: [TapTest]
    }

    // The medication, age choice, age group, dose hours and number of days used in the sample data
    static let medication = Store.Medication(name: "Carbidopa-levodopa", schedule: "1 tablet at 8 AM, 2 PM and 8 PM")
    static let ageChoice = "70–79"
    static let bracket = "70s"
    static let doseHours = [8, 14, 20]
    static let days = 21

    // Right hand check ins, as days ago, hour and minute, spread across every stage after a dose
    static let rightCheckins: [(Int, Int, Int)] = [
        (21, 9, 40), (20, 12, 10), (19, 15, 20), (18, 17, 45), (16, 8, 30), (15, 21, 10), (14, 11, 5),
        (13, 16, 30), (12, 9, 15), (11, 19, 30), (10, 14, 40), (9, 10, 30), (8, 13, 30), (7, 15, 50),
        (6, 22, 30), (5, 8, 45), (4, 18, 10), (3, 9, 50), (2, 16, 20), (1, 10, 10),
    ]

    // Left hand check ins, close in time to right hand ones
    static let leftCheckins: [(Int, Int, Int)] = [(6, 17, 5), (2, 11, 30)]

    // Practice tries for each exercise, as days ago and the level, where 0 is Level 1
    static let practice: [(exercise: String, tries: [(Int, Int)])] = [
        ("big-writing", [(20, 0), (17, 0), (14, 1), (12, 1), (9, 1), (6, 2), (4, 2), (2, 2)]),
        ("steady-tracing", [(19, 0), (16, 0), (13, 1), (10, 1), (7, 1), (5, 2), (3, 2), (1, 2)]),
        ("rhythm", [(18, 0), (15, 0), (11, 0), (8, 1), (4, 1), (1, 1)]),
        ("hand-skills", [(21, 0), (17, 1), (12, 1), (9, 2), (5, 2), (2, 2)]),
    ]

    // Finger tapping tests, as days ago, hand, taps a second, how wide the fingers open,
    // and how much the opening shrinks by the last tap
    static let tapping: [(Int, String, Double, Double, Double)] = [
        (19, "right", 2.6, 0.82, 0.18), (13, "right", 2.8, 0.85, 0.15), (8, "right", 2.7, 0.8, 0.2),
        (3, "right", 3.0, 0.86, 0.12), (3, "left", 2.3, 0.72, 0.25),
    ]

    // Random numbers that come out the same every time for the same starting state
    struct Dice {
        var state: UInt64

        // Give back the next random number from 0 up to 1
        mutating func next() -> Double {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            return Double(z >> 11) / Double(UInt64(1) << 53)
        }

        // Give back a random number between low and high
        mutating func between(_ low: Double, _ high: Double) -> Double { low + (high - low) * next() }

        // Give back a bell shaped random number centered on 0 with a spread of 1
        mutating func normal() -> Double {
            let u = max(next(), 1e-12), v = next()
            return sqrt(-2 * log(u)) * cos(2 * .pi * v)
        }
    }

    // Make one spiral traced over the guide from the middle out, as the pad records it
    // seconds is how long it takes, tremor is how far the line shakes in points, and drift is how far it wanders off the guide
    static func spiral(seconds: Double, tremor: Double, drift: Double, dice: inout Dice) -> [Sample] {

        // The pad size, the spiral's largest radius, its turns, and the samples per second
        let size = 620.0, maxR = size / 2 - 20, turns = 4.0, hz = 100.0
        let n = Int(seconds * hz)

        // Pick the speeds and starting points of the slow wander, the quick wobble and the tremor
        let slow = (0..<2).map { _ in (hz: dice.between(0.2, 0.7), phase: dice.between(0, 2 * .pi)) }
        let quick = (0..<3).map { _ in (hz: dice.between(2.2, 3.8), phase: dice.between(0, 2 * .pi)) }
        let tremorHz = dice.between(4.5, 6), tremorPhase = dice.between(0, 2 * .pi)

        // Pick three spots where the line strays further from the guide
        let strays = (0..<3).map { _ in (at: dice.between(0.15, 0.95), size: dice.between(-1.6, 1.6) * drift, width: dice.between(0.015, 0.04)) }
        let speedPhase = dice.between(0, 2 * .pi), unevenness = dice.between(0.15, 0.3)

        // Make each sample
        return (0..<n).map { i in
            let t = Double(i) / hz
            let u = Double(i) / Double(n - 1)

            // Move along the spiral a little faster and slower over time, always forward
            let progress = min(1, max(0, u + unevenness * sin(4 * .pi * u + speedPhase) / (4 * .pi)))
            let theta = progress * turns * 2 * .pi

            // Add up the noise, tremor, wander, wobble and strays to get how far the point sits off the guide
            var off = 0.3 * dice.normal() + tremor * sin(2 * .pi * tremorHz * t + tremorPhase)
            for s in slow { off += 0.6 * drift * sin(2 * .pi * s.hz * t + s.phase) }
            for q in quick { off += quickShare * drift * sin(2 * .pi * q.hz * t + q.phase) }
            for s in strays { off += s.size * exp(-pow((progress - s.at) / s.width, 2)) }

            // Turn the angle and radius into a point on the pad, with a slowly changing pressure
            let r = progress * maxR + off
            return Sample(t: t, x: size / 2 + r * cos(theta), y: size / 2 + r * sin(theta),
                          pressure: 0.38 + 0.06 * sin(2 * .pi * 0.4 * t) + 0.02 * dice.normal())
        }
    }

    // How big the quick wobble is next to the slow wander
    static let quickShare = 0.2

    // Make a finger tapping test at 30 frames a second, where gap is the fingertip distance over the hand's size
    static func tapSignal(rate: Double, opening: Double, fade: Double, dice: inout Dice) -> [TapSample] {

        // Make the test long enough for about 10 taps
        let fps = 30.0, seconds = 10.4 / rate
        return (0..<Int(seconds * fps)).map { i in
            let t = Double(i) / fps

            // Shrink the opening over time, swing the fingers open and closed, and add a little noise
            let wide = opening * (1 - fade * t / seconds)
            let swing = 0.5 + 0.5 * cos(2 * .pi * rate * t + 0.15 * sin(2 * .pi * 0.7 * t))
            return TapSample(t: t, gap: 0.08 + wide * swing + 0.012 * dice.normal())
        }
    }

    // Give back how long a spiral takes, how much it shakes and how far it wanders, by hours since the last dose
    // The left hand is a little slower and shakier
    static func drawing(hoursSinceDose: Double, left: Bool, dice: inout Dice) -> (seconds: Double, tremor: Double, drift: Double) {

        // Pick the base values for the time since the dose
        let base: (seconds: Double, tremor: Double, drift: Double)
        switch hoursSinceDose {
        case ..<1: base = (16, 0.8, 16)
        case ..<2: base = (14, 0.5, 15)
        case ..<3: base = (15, 0.6, 15)
        case ..<4: base = (18, 1.0, 18)
        default: base = (21, 1.3, 20)
        }

        // Scale them up for the left hand and add a little randomness
        let other = left ? 1.15 : 1.0
        return (base.seconds * other + dice.between(-1, 1), base.tremor * other * other + dice.between(-0.1, 0.1),
                base.drift * other + dice.between(-1, 1))
    }

    // Give back the hours since the last dose before this time, or 12 if there was none
    static func hoursSinceDose(_ time: Date, _ doses: [Dose]) -> Double {
        let ms = Int(time.timeIntervalSince1970 * 1000)
        guard let last = doses.filter({ d in d.ts <= ms }).map({ d in d.ts }).max() else { return 12 }
        return Double(ms - last) / 3_600_000
    }

    // Give back the date that is daysAgo days before now, at this hour and minute
    static func at(_ daysAgo: Int, _ hour: Int, _ minute: Int, now: Date, calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    // Turn a date into milliseconds since 1970
    static func ms(_ date: Date) -> Int { Int(date.timeIntervalSince1970 * 1000) }

    // Make all the sample data, oldest first
    // It throws only if a made up spiral can't be measured
    static func make(model: Score.Model, reference: Score.Reference, now: Date, calendar: Calendar = .current) throws -> Made {
        var dice = Dice(state: 2026)

        // Three doses a day, none later than now
        var doses: [Dose] = []
        for daysAgo in stride(from: days, through: 0, by: -1) {
            for hour in doseHours {
                let when = at(daysAgo, hour, dice.next() < 0.5 ? 0 : 5, now: now, calendar: calendar)
                if when <= now { doses.append(Dose(ts: ms(when))) }
            }
        }

        // Put the right and left hand check ins in time order
        let right = rightCheckins.map { c in (when: at(c.0, c.1, c.2, now: now, calendar: calendar), hand: "right") }
        let left = leftCheckins.map { c in (when: at(c.0, c.1, c.2, now: now, calendar: calendar), hand: "left") }
        let plan = (right + left).sorted { a, b in a.when < b.when }

        // Make each check in with three spirals, measured and scored like a real one
        var records: [AssessmentRecord] = []
        for item in plan {
            let style = drawing(hoursSinceDose: hoursSinceDose(item.when, doses), left: item.hand == "left", dice: &dice)
            var trials: [AssessmentTrial] = []
            for _ in 0..<3 {
                let samples = spiral(seconds: style.seconds + dice.between(-0.5, 0.5), tremor: style.tremor, drift: style.drift, dice: &dice)
                let features = try NTFeatures.featuresFromTrace(Trace(task: "spiral", hand: item.hand, inputType: "pencil", deviceLabel: "iPad", samples: samples))
                trials.append(AssessmentTrial(samples: samples, strokeStarts: [0], features: features, path: replayPath(samples, [0])))
            }
            let result = Score.scoreSession(trials.map { t in t.features }, model, reference, bracket)
            records.append(AssessmentRecord(id: nil, ts: ms(item.when), task: "spiral", hand: item.hand, ageChoice: ageChoice,
                                            bracketChoice: bracket, inputType: "pencil", deviceLabel: "iPad", trials: trials,
                                            features: result.features, result: result))
        }

        // Make the practice tries with empty measures, and set each exercise to its highest level
        var tries: [TrainingTry] = []
        var levels: [String: Train.LevelState] = [:]
        for (exercise, list) in practice {
            let steps = Train.exercises[exercise]?.levels ?? []
            for (daysAgo, level) in list {
                let when = at(daysAgo, Int(dice.between(10, 18)), Int(dice.between(0, 59)), now: now, calendar: calendar)
                let hit = dice.next() < 0.75
                tries.append(TrainingTry(id: nil, ts: ms(when), exercise: exercise, level: level,
                                         target: level < steps.count ? steps[level] : 0, counted: true, hit: hit,
                                         reachedTarget: hit, slower: false, shakier: false, measures: [:],
                                         vs: Train.Vs(pace: nil, smoothness: nil), inputType: exercise == "hand-skills" ? "touch" : "pencil",
                                         path: nil, geometry: nil, results: nil))
            }
            let top = list.map { t in t.1 }.max() ?? 0
            levels[exercise] = Train.LevelState(level: top, hits: 1, misses: 0, last: top > 0 ? "up" : nil)
        }
        tries.sort { a, b in a.ts < b.ts }

        // Make the finger tapping tests, measured by tapping.js like a real test
        var tapTests: [TapTest] = []
        for test in tapping {
            let when = at(test.0, 11, test.1 == "right" ? 0 : 6, now: now, calendar: calendar)
            let samples = tapSignal(rate: test.2, opening: test.3, fade: test.4, dice: &dice)
            tapTests.append(TapTest(ts: ms(when), hand: test.1, result: Tapping.analyzeTaps(samples)))
        }

        return Made(records: records, doses: doses, tries: tries, levels: levels, taps: tapTests)
    }

    // Replace everything on this device with the sample data
    static func load(model: Score.Model, reference: Score.Reference, now: Date = Date(), calendar: Calendar = .current) async throws {

        // Make the data on the JavaScript thread
        let made = try await JSCore.background { try make(model: model, reference: reference, now: now, calendar: calendar) }

        // Clear the saved data, then save every check in, dose, try, level and tap test
        try await Store.clearPersonalData()
        for record in made.records { _ = try await Store.saveAssessment(record) }
        for dose in made.doses { _ = try await Store.saveDose(dose) }
        for practiceTry in made.tries { _ = try await Store.saveTrainingTry(practiceTry) }
        for (exercise, state) in made.levels { Store.setTrainingState(exercise, state) }
        for test in made.taps { Store.saveTapTest(test) }

        // Save the medication and the settings for the sample person
        Store.setMedication(medication)
        Store.setPrefs { p in
            p.ageChoice = ageChoice
            p.hand = "right"
            p.consented = true
            p.onboarded = true
        }
    }
}
