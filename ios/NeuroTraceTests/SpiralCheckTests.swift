import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

// A spiral traced from the middle out the way the guide asks, timed in seconds like the pad records.
// tremorPx adds a 5 Hz in-and-out shake, the band Parkinson's tremor sits in
private func spiral(seconds: Double, tremorPx: Double = 0, turns: Double = 3, radius: Double = 150, seed: UInt32 = 1) -> Trace {
    let rand = rng(seed), hz = 120.0
    var samples: [Sample] = []
    for i in 0..<Int(seconds * hz) {
        let t = Double(i) / hz
        let theta = turns * 2 * Double.pi * t / seconds
        let r = radius * t / seconds + tremorPx * sin(2 * Double.pi * 5 * t)
        samples.append(Sample(t: t, x: 300 + r * cos(theta) + (rand() - 0.5) * 0.6, y: 300 + r * sin(theta) + (rand() - 0.5) * 0.6))
    }
    return Trace(task: "spiral", hand: "right", inputType: "touch", deviceLabel: "test", samples: samples)
}

// Random loops all over the pad - what "just drawing random stuff" looks like
private func scribble(seconds: Double, seed: UInt32) -> Trace {
    let rand = rng(seed), hz = 120.0
    let parts = (0..<4).map { _ in (a: 40 + rand() * 80, f: 0.5 + rand() * 2.5, px: rand() * 6.3, py: rand() * 6.3) }
    var samples: [Sample] = []
    for i in 0..<Int(seconds * hz) {
        let t = Double(i) / hz
        let x = parts.reduce(300.0) { s, p in s + p.a * sin(2 * Double.pi * p.f * t + p.px) }
        let y = parts.reduce(300.0) { s, p in s + p.a * cos(2 * Double.pi * p.f * 1.3 * t + p.py) }
        samples.append(Sample(t: t, x: x, y: y))
    }
    return Trace(task: "spiral", hand: "right", inputType: "touch", deviceLabel: "test", samples: samples)
}

final class SpiralCheckTests: XCTestCase {
    func testSpiralCheck() throws {
        XCTAssertNil(SpiralCheck.problem(["spiral_mean_deviation": 0.149, "spiral_duration": 4.1]))
        // The worst and the fastest real spirals among the 112 training people both get through

        XCTAssertEqual(SpiralCheck.problem(["spiral_mean_deviation": 0.21, "spiral_duration": 12]), .offGuide)
        XCTAssertEqual(SpiralCheck.problem(["spiral_mean_deviation": 0.05, "spiral_duration": 2.4]), .tooFast)
        XCTAssertEqual(SpiralCheck.problem(["spiral_mean_deviation": 0.3, "spiral_duration": 1]), .offGuide)
        XCTAssertNil(SpiralCheck.problem(["spiral_mean_deviation": .nan, "spiral_duration": .nan]))
        XCTAssertNil(SpiralCheck.problem([:]))

        let real: [(seconds: Double, tremor: Double, seed: UInt32)] = [(8, 0, 1), (20, 0, 2), (5, 0, 3), (15, 12, 4), (15, 20, 5), (15, 25, 6)]
        for c in real {
            let f = try NTFeatures.featuresFromTrace(spiral(seconds: c.seconds, tremorPx: c.tremor, seed: c.seed))
            XCTAssertNil(SpiralCheck.problem(f), "\(c.seconds) s spiral with a ±\(c.tremor) px tremor was sent back (mean deviation \(f["spiral_mean_deviation"] ?? .nan))")
        }
        // Shaky spirals get through. ±25 px on a 150 px spiral is a bigger shake than anyone in the
        // training data, Parkinson's included, and it still counts

        let quick = try NTFeatures.featuresFromTrace(spiral(seconds: 2))
        XCTAssertEqual(SpiralCheck.problem(quick), .tooFast)

        for seed in UInt32(1)...40 {
            for seconds in [1.2, 6.0] {
                let f = try? NTFeatures.featuresFromTrace(scribble(seconds: seconds, seed: seed))
                XCTAssertTrue(f == nil || SpiralCheck.problem(f!) != nil, "scribble \(seed), \(seconds) s got through")
            }
        }
        // No scribble gets scored on the first try: either featuresFromTrace refuses it as too little
        // of a spiral, or SpiralCheck sends it back

        print("SPIRAL CHECK OK")
    }
}
