import Foundation

// What the Training tab suggests and counts. Plain functions, so the tests can check them

enum Practice {
    static let exercises = ["big-writing", "rhythm", "steady-tracing", "hand-skills"]

    // The exercise that works on each measure. Main wobble frequency isn't something to practice, so it has none
    static let exerciseFor: [String: String] = [
        "spiral_duration": "big-writing", "spiral_mean_speed": "big-writing",
        "spiral_std_speed": "rhythm", "spiral_ldlj": "rhythm", "spiral_sparc": "rhythm",
        "spiral_max_deviation": "steady-tracing", "spiral_mean_deviation": "steady-tracing", "spiral_std_deviation": "steady-tracing",
        "spiral_major_reversals": "steady-tracing", "spiral_tremor_4_6": "steady-tracing", "spiral_tremor_6_12": "steady-tracing",
    ]

    struct Focus: Equatable {
        var exercise: String
        // The measure that picked it, nil when no measure in the newest check-in points to an exercise
        var measure: String?
        // The newest check-in, nil when there isn't one yet
        var checkinTs: Int?
    }

    // Today's focus: the exercise for the measure that stood out most in the newest check-in. With no
    // check-in, or none that stood out, the exercise practiced least recently, so each one gets a turn
    static func focus(latest: AssessmentRecord?, lastPracticed: [String: Int]) -> Focus {
        if let latest, let result = latest.result {
            for key in Score.pushedUp(result) {
                if let exercise = exerciseFor[key] { return Focus(exercise: exercise, measure: key, checkinTs: latest.ts) }
            }
        }
        let next = exercises.min { a, b in (lastPracticed[a] ?? Int.min) < (lastPracticed[b] ?? Int.min) } ?? exercises[0]
        return Focus(exercise: next, measure: nil, checkinTs: latest?.result == nil ? nil : latest?.ts)
    }

    // When each exercise was last practiced. Tries come newest first, so the first one seen is the latest
    static func lastPracticed(_ tries: [TrainingTry]) -> [String: Int] {
        var last: [String: Int] = [:]
        for t in tries where last[t.exercise] == nil { last[t.exercise] = t.ts }
        return last
    }

    // Whether any of these times falls on the same day as now
    static func doneToday(_ times: [Int], now: Date, calendar: Calendar = .current) -> Bool {
        times.contains { ts in calendar.isDate(Date(timeIntervalSince1970: Double(ts) / 1000), inSameDayAs: now) }
    }

    // This week, from the first day of the week in the person's calendar: whether each day had a practice
    // try. nil for days still to come
    static func week(_ tryTimes: [Int], now: Date, calendar: Calendar = .current) -> [Bool?] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<7).map { offset -> Bool? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            if day > today { return nil }
            return tryTimes.contains { ts in calendar.isDate(Date(timeIntervalSince1970: Double(ts) / 1000), inSameDayAs: day) }
        }
    }

    // The days a practice try was made in the last `days` days, today included
    static func daysPracticed(_ tryTimes: [Int], days: Int, now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return 0 }
        let practiced = Set(tryTimes.compactMap { ts -> Date? in
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(ts) / 1000))
            return day >= first && day <= today ? day : nil
        })
        return practiced.count
    }
}
