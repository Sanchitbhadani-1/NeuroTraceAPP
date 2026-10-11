import Foundation

// What the Training tab suggests and counts. Plain functions, so the tests can check them

enum Practice {
    // Whether any of these times falls on the same day as now
    static func doneToday(_ times: [Int], now: Date, calendar: Calendar = .current) -> Bool {
        times.contains { ts in calendar.isDate(Date(timeIntervalSince1970: Double(ts) / 1000), inSameDayAs: now) }
    }
}
