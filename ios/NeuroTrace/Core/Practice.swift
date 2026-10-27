// PRACTICE.SWIFT PICKS WHAT THE TRAINING TAB SUGGESTS AND COUNTS THE DAYS PRACTICED
// IT HOLDS PLAIN FUNCTIONS THAT THE TESTS CALL

import Foundation

// Picks today's exercise and counts practice tries
enum Practice {

    // Every exercise, in order
    static let exercises = ["big-writing", "rhythm", "steady-tracing", "hand-skills"]

    // The exercise for each measure, with no exercise for main wobble frequency
    static let exerciseFor: [String: String] = [
        "spiral_duration": "big-writing", "spiral_mean_speed": "big-writing",
        "spiral_std_speed": "rhythm", "spiral_ldlj": "rhythm", "spiral_sparc": "rhythm",
        "spiral_max_deviation": "steady-tracing", "spiral_mean_deviation": "steady-tracing", "spiral_std_deviation": "steady-tracing",
        "spiral_major_reversals": "steady-tracing", "spiral_tremor_4_6": "steady-tracing", "spiral_tremor_6_12": "steady-tracing",
    ]

    // Today's exercise and what picked it
    struct Focus: Equatable {
        var exercise: String

        // The measure that picked it, or nil when no measure in the newest check in picked one
        var measure: String?

        // The time of the newest check in, or nil when there isn't one yet
        var checkinTs: Int?
    }

    // Pick today's exercise from the first measure that pushed the newest check in up
    // With no check in, or no measure that pushed it up, pick the exercise practiced longest ago
    static func focus(latest: AssessmentRecord?, lastPracticed: [String: Int]) -> Focus {

        // Use the first measure that pushed the result up and has an exercise
        if let latest, let result = latest.result {
            for key in Score.pushedUp(result) {
                if let exercise = exerciseFor[key] { return Focus(exercise: exercise, measure: key, checkinTs: latest.ts) }
            }
        }

        // Otherwise pick the exercise practiced longest ago, with never practiced coming first
        let next = exercises.min { a, b in (lastPracticed[a] ?? Int.min) < (lastPracticed[b] ?? Int.min) } ?? exercises[0]
        return Focus(exercise: next, measure: nil, checkinTs: latest?.result == nil ? nil : latest?.ts)
    }

    // When each exercise was last practiced, keeping the first time seen for each one from a newest first list
    static func lastPracticed(_ tries: [TrainingTry]) -> [String: Int] {
        var last: [String: Int] = [:]
        for t in tries where last[t.exercise] == nil { last[t.exercise] = t.ts }
        return last
    }

    // True if any of these times falls on the same day as now
    static func doneToday(_ times: [Int], now: Date, calendar: Calendar = .current) -> Bool {
        times.contains { ts in calendar.isDate(Date(timeIntervalSince1970: Double(ts) / 1000), inSameDayAs: now) }
    }

    // For each day this week, from the first day of the week in the person's calendar, whether it had a practice try
    // Days still to come are nil
    static func week(_ tryTimes: [Int], now: Date, calendar: Calendar = .current) -> [Bool?] {

        // Find the start of this week and the start of today
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        let today = calendar.startOfDay(for: now)

        // Go through the 7 days and check each one for a try
        return (0..<7).map { offset -> Bool? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: interval.start) else { return nil }
            if day > today { return nil }
            return tryTimes.contains { ts in calendar.isDate(Date(timeIntervalSince1970: Double(ts) / 1000), inSameDayAs: day) }
        }
    }

    // Count the days with a practice try in the last `days` days, today included
    static func daysPracticed(_ tryTimes: [Int], days: Int, now: Date, calendar: Calendar = .current) -> Int {

        // Find the first day to count
        let today = calendar.startOfDay(for: now)
        guard let first = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return 0 }

        // Turn each try into its day, keep the days in range, and count the different days
        let practiced = Set(tryTimes.compactMap { ts -> Date? in
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(ts) / 1000))
            return day >= first && day <= today ? day : nil
        })
        return practiced.count
    }
}
