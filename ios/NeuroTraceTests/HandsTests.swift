// HANDSTESTS.SWIFT CHECKS HAND PAIRING, MISSING VALUES, AND SORTING BY DIFFERENCE
// IT USES THE SAME CASES AS APP/TOOLS/HANDS-CHECK.MJS

import Foundation
import XCTest
// Use the NeuroTraceCore module when it exists, or the app if it doesn't
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

// One day in milliseconds
private let DAY = 86_400_000.0

// A made up check in with a time, hand, pen or finger, and measures
private struct Rec: HandedCheckin {
    var ts: Int
    var hand: String
    var inputType: String?
    var measurePct: [String: Double]
}

// Makes a check in on a given day, with a pencil and no measures unless given
private func rec(_ hand: String, _ day: Double, _ inputType: String = "pencil", _ measurePct: [String: Double] = [:]) -> Rec {
    Rec(ts: Int((day * DAY).rounded()), hand: hand, inputType: inputType, measurePct: measurePct)
}

// Turns a day into milliseconds
private func at(_ day: Double) -> Int { Int((day * DAY).rounded()) }

// The tests for comparing the two hands
final class HandsTests: XCTestCase {

    // Check how check ins are paired and how the hands are compared
    func testHands() {

        // Check that there is no pair with no check ins or only one hand
        XCTAssertNil(Hands.latestPair([Rec]()))
        XCTAssertNil(Hands.latestPair([rec("left", 10), rec("left", 9)]))

        // Check that a left and a right a day apart make a pair
        var pair = Hands.latestPair([rec("left", 10), rec("right", 9)])
        XCTAssertEqual(pair?.left.ts, at(10))
        XCTAssertEqual(pair?.right.ts, at(9))

        // Check that a pencil and a finger don't pair, 8 days apart don't pair, and 7 days apart do
        XCTAssertNil(Hands.latestPair([rec("left", 10, "pencil"), rec("right", 9, "finger")]))
        XCTAssertNil(Hands.latestPair([rec("left", 20), rec("right", 12)]))
        XCTAssertNotNil(Hands.latestPair([rec("left", 19), rec("right", 12)]))

        // Check that the newest left and the newest right are paired
        pair = Hands.latestPair([rec("left", 18), rec("left", 16), rec("right", 15), rec("right", 12)])
        XCTAssertEqual(pair?.left.ts, at(18))
        XCTAssertEqual(pair?.right.ts, at(15))

        // Check that older check ins don't change the pair
        pair = Hands.latestPair([rec("left", 18), rec("left", 16), rec("right", 16), rec("right", 3), rec("left", 2)])
        XCTAssertEqual(pair?.left.ts, at(18))
        XCTAssertEqual(pair?.right.ts, at(16))

        // Check that the newest left is used when the list is oldest first
        pair = Hands.latestPair([rec("right", 1), rec("left", 2), rec("left", 3)])
        XCTAssertEqual(pair?.left.ts, at(3))

        // Check that the newest pair is used when there are finger and pencil pairs
        pair = Hands.latestPair([rec("left", 10, "finger"), rec("right", 10, "finger"), rec("left", 8, "pencil"), rec("right", 8, "pencil")])
        XCTAssertEqual(pair?.left.inputType, "finger")

        // Check that comparing hands skips missing values and sorts by the biggest difference first
        let left = rec("left", 10, "pencil", ["spiral_duration": 0.5, "spiral_mean_speed": 0.31, "spiral_ldlj": 0.4, "spiral_sparc": .nan])
        let right = rec("right", 10, "pencil", ["spiral_duration": 0.7, "spiral_mean_speed": 0.68, "spiral_ldlj": 0.3, "spiral_sparc": 0.5])
        let rows = Hands.compareHands(left: left.measurePct, right: right.measurePct)
        XCTAssertEqual(rows.map { r in r.key }, ["spiral_mean_speed", "spiral_duration", "spiral_ldlj"])
        XCTAssertEqual(rows[0].left, 0.31)
        XCTAssertEqual(rows[0].right, 0.68)
        XCTAssertTrue(abs(rows[0].diff - -0.37) < 1e-9)
        XCTAssertTrue(rows[2].diff > 0)

        // Check that only measures in the given order are compared, and no measures gives no rows
        XCTAssertEqual(Hands.compareHands(left: left.measurePct, right: right.measurePct, order: ["spiral_ldlj", "spiral_tremor_4_6"]).map { r in r.key }, ["spiral_ldlj"])
        XCTAssertEqual(Hands.compareHands(left: rec("left", 1).measurePct, right: right.measurePct), [])

        // Check that two differences of the same size stay in the usual measure order
        let evenLeft = rec("left", 1, "pencil", ["spiral_duration": 0.5, "spiral_mean_speed": 0.25])
        let evenRight = rec("right", 1, "pencil", ["spiral_duration": 0.75, "spiral_mean_speed": 0])
        XCTAssertEqual(Hands.compareHands(left: evenLeft.measurePct, right: evenRight.measurePct).map { r in r.key }, ["spiral_duration", "spiral_mean_speed"])

        print("HANDS OK")
    }
}
