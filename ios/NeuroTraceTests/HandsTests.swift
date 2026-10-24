// test hand pairing, missing values, and sorting by difference. The same cases as Mihir's
// app/tools/hands-check.mjs, so the Swift and JavaScript versions agree

import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

private let DAY = 86_400_000.0

private struct Rec: HandedCheckin {
    var ts: Int
    var hand: String
    var inputType: String?
    var measurePct: [String: Double]
}

private func rec(_ hand: String, _ day: Double, _ inputType: String = "pencil", _ measurePct: [String: Double] = [:]) -> Rec {
    Rec(ts: Int((day * DAY).rounded()), hand: hand, inputType: inputType, measurePct: measurePct)
}

private func at(_ day: Double) -> Int { Int((day * DAY).rounded()) }

final class HandsTests: XCTestCase {
    func testHands() {
        XCTAssertNil(Hands.latestPair([Rec]()))
        XCTAssertNil(Hands.latestPair([rec("left", 10), rec("left", 9)]))

        var pair = Hands.latestPair([rec("left", 10), rec("right", 9)])
        XCTAssertEqual(pair?.left.ts, at(10))
        XCTAssertEqual(pair?.right.ts, at(9))

        XCTAssertNil(Hands.latestPair([rec("left", 10, "pencil"), rec("right", 9, "finger")]))
        XCTAssertNil(Hands.latestPair([rec("left", 20), rec("right", 12)]))
        XCTAssertNotNil(Hands.latestPair([rec("left", 19), rec("right", 12)]))

        pair = Hands.latestPair([rec("left", 18), rec("left", 16), rec("right", 15), rec("right", 12)])
        XCTAssertEqual(pair?.left.ts, at(18))
        XCTAssertEqual(pair?.right.ts, at(15))

        pair = Hands.latestPair([rec("left", 18), rec("left", 16), rec("right", 16), rec("right", 3), rec("left", 2)])
        XCTAssertEqual(pair?.left.ts, at(18))
        XCTAssertEqual(pair?.right.ts, at(16))

        pair = Hands.latestPair([rec("right", 1), rec("left", 2), rec("left", 3)])
        XCTAssertEqual(pair?.left.ts, at(3))

        pair = Hands.latestPair([rec("left", 10, "finger"), rec("right", 10, "finger"), rec("left", 8, "pencil"), rec("right", 8, "pencil")])
        XCTAssertEqual(pair?.left.inputType, "finger")

        let left = rec("left", 10, "pencil", ["spiral_duration": 0.5, "spiral_mean_speed": 0.31, "spiral_ldlj": 0.4, "spiral_sparc": .nan])
        let right = rec("right", 10, "pencil", ["spiral_duration": 0.7, "spiral_mean_speed": 0.68, "spiral_ldlj": 0.3, "spiral_sparc": 0.5])
        let rows = Hands.compareHands(left: left.measurePct, right: right.measurePct)
        XCTAssertEqual(rows.map { r in r.key }, ["spiral_mean_speed", "spiral_duration", "spiral_ldlj"])
        XCTAssertEqual(rows[0].left, 0.31)
        XCTAssertEqual(rows[0].right, 0.68)
        XCTAssertTrue(abs(rows[0].diff - -0.37) < 1e-9)
        XCTAssertTrue(rows[2].diff > 0)
        XCTAssertEqual(Hands.compareHands(left: left.measurePct, right: right.measurePct, order: ["spiral_ldlj", "spiral_tremor_4_6"]).map { r in r.key }, ["spiral_ldlj"])
        XCTAssertEqual(Hands.compareHands(left: rec("left", 1).measurePct, right: right.measurePct), [])

        let evenLeft = rec("left", 1, "pencil", ["spiral_duration": 0.5, "spiral_mean_speed": 0.25])
        let evenRight = rec("right", 1, "pencil", ["spiral_duration": 0.75, "spiral_mean_speed": 0])
        XCTAssertEqual(Hands.compareHands(left: evenLeft.measurePct, right: evenRight.measurePct).map { r in r.key }, ["spiral_duration", "spiral_mean_speed"])

        print("HANDS OK")
    }
}
