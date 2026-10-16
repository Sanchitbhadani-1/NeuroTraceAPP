import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

final class StoreTests: XCTestCase {
    func testStore() {
        let suite = "neurotrace-store-check-\(UUID().uuidString)"
        let saved = Store.defaults
        Store.defaults = UserDefaults(suiteName: suite)!
        defer {
            Store.defaults.removePersistentDomain(forName: suite)
            Store.defaults = saved
        }

        for _ in 0..<200 {
            let id = Store.newSubjectId(Set())
            XCTAssertTrue(id.range(of: "^[0-9a-f]{6}$", options: .regularExpression) != nil, "\"\(id)\" is not 6 lowercase hex chars")
        }

        do {
            let existing: Set<String> = ["aaaaaa", "bbbbbb"]
            for _ in 0..<200 {
                let id = Store.newSubjectId(existing)
                XCTAssertTrue(!existing.contains(id), "newSubjectId returned a collision: \(id)")
            }
        }

        do {
            var seen = Set<String>()
            for _ in 0..<500 {
                let id = Store.newSubjectId(seen)
                XCTAssertTrue(!seen.contains(id))
                seen.insert(id)
            }
        }

        XCTAssertEqual(Store.getPrefs(), Store.Prefs(
            onboarded: false, consented: false, signedIn: false, ageChoice: nil,
            hand: "right", theme: "auto", accent: "blue", motion: "auto"
        ))
        Store.setPrefs { p in p.onboarded = true }

        print("STORE OK")
    }
}
