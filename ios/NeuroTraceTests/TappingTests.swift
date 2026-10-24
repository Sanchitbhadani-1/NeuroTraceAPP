// check tap detection, smoothing, holes and the summary numbers. The same cases as Aryan's
// app/tools/tapping-check.mjs, so the Swift and JavaScript versions agree

import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

private let fps = 30.0

// Made-up camera frames: fingers start open, close once per cycle (a tap). hz and amp take progress 0..1
private func taps(n: Double = 10, hz: (Double) -> Double = { _ in 2.5 }, amp: (Double) -> Double = { _ in 1 }) -> [TapSample] {
    var samples: [TapSample] = []
    var phase = 0.0
    var i = 0
    while phase <= 2 * Double.pi * n {
        let p = phase / (2 * Double.pi * n)
        samples.append(TapSample(t: Double(i) / fps, gap: 0.1 + amp(p) * (1 + cos(phase)) / 2))
        phase += 2 * Double.pi * hz(p) / fps
        i += 1
    }
    return samples
}

private func hold(_ seconds: Double, _ gap: Double?) -> [TapSample] {
    (0..<Int((seconds * fps).rounded())).map { i in TapSample(t: Double(i) / fps, gap: gap) }
}

private func join(_ parts: [TapSample]...) -> [TapSample] {
    var out: [TapSample] = []
    for part in parts {
        let start = out.isEmpty ? 0 : out[out.count - 1].t + 1 / fps
        for s in part { out.append(TapSample(t: start + s.t, gap: s.gap)) }
    }
    return out
}

private func noNaN(_ r: TapResult, file: StaticString = #filePath, line: UInt = #line) {
    let values = [r.duration, r.rate, r.rhythmCv, r.meanOpening, r.openingChange, r.rateChange].compactMap { v in v } + r.tapTimes + r.openings
    for v in values { XCTAssertTrue(v.isFinite, "\(v) isn't finite", file: file, line: line) }
}

private func near(_ a: Double?, _ b: Double, _ tol: Double, _ label: String, file: StaticString = #filePath, line: UInt = #line) {
    guard let a else { return XCTFail("\(label) is nil", file: file, line: line) }
    XCTAssertTrue(abs(a - b) <= tol, "\(label): \(a) not within \(tol) of \(b)", file: file, line: line)
}

private func result(_ taps: Int, rate: Double?, openingChange: Double? = nil, pauses: Int = 0) -> TapResult {
    TapResult(counted: taps >= Tapping.minTaps, taps: taps, duration: rate.map { r in Double(taps - 1) / r }, rate: rate, rhythmCv: 0.05,
              meanOpening: 1, openingChange: openingChange, rateChange: 0, pauses: pauses, tapTimes: [], openings: [])
}

final class TappingTests: XCTestCase {
    func testTapping() {
        // Steady 2.5 taps/s: dips land at 0.2, 0.6, 1.0 s ...
        do {
            let r = Tapping.analyzeTaps(taps())
            noNaN(r)
            XCTAssertEqual(r.taps, 10)
            XCTAssertTrue(r.counted)
            XCTAssertEqual(r.tapTimes.count, 10)
            for (k, t) in r.tapTimes.enumerated() { near(t, 0.2 + 0.4 * Double(k), 0.5 / fps, "tap \(k) time") }
            XCTAssertEqual(r.openings.count, 10)
            near(r.rate, 2.5, 0.1, "rate")
            near(r.duration, 3.6, 0.07, "duration")
            XCTAssertTrue((r.rhythmCv ?? 1) < 0.05, "rhythmCv \(String(describing: r.rhythmCv))")
            near(r.openingChange, 0, 0.05, "openingChange")
            near(r.rateChange, 0, 0.05, "rateChange")
            near(r.meanOpening, 1.05, 0.06, "meanOpening")
            XCTAssertEqual(r.pauses, 0)
        }

        // Openings shrink to 60%: openingChange goes negative, speed stays put
        do {
            let r = Tapping.analyzeTaps(taps(amp: { p in 1 - 0.4 * p }))
            noNaN(r)
            XCTAssertEqual(r.taps, 10)
            XCTAssertTrue((r.openingChange ?? 0) < -0.2, "openingChange \(String(describing: r.openingChange))")
            near(r.rateChange, 0, 0.05, "rateChange")
        }

        // Slows from 3 to 2 taps/s: rateChange goes negative, opening stays put
        do {
            let r = Tapping.analyzeTaps(taps(hz: { p in 3 - p }))
            noNaN(r)
            XCTAssertEqual(r.taps, 10)
            XCTAssertTrue((r.rateChange ?? 0) < -0.15, "rateChange \(String(describing: r.rateChange))")
            near(r.openingChange, 0, 0.05, "openingChange")
        }

        // One frame reads "closed" mid-opening: smoothing keeps it from counting as a tap
        do {
            let samples = taps().enumerated().map { (i, s) in i == 36 ? TapSample(t: s.t, gap: 0.1) : s }
            XCTAssertEqual(Tapping.analyzeTaps(samples).taps, 10)
        }

        // One wild frame (gap 4) plus smaller late taps: trim keeps those taps counted
        do {
            let samples = taps(amp: { p in p < 0.5 ? 1 : 0.55 }).enumerated().map { (i, s) in i == 20 ? TapSample(t: s.t, gap: 4) : s }
            XCTAssertEqual(Tapping.analyzeTaps(samples).taps, 10)
        }

        // Single missing frames are joined over, no taps lost
        do {
            let samples = taps().enumerated().map { (i, s) in i % 7 == 3 ? TapSample(t: s.t, gap: nil) : s }
            XCTAssertEqual(Tapping.analyzeTaps(samples).taps, 10)
        }

        // Hand vanishes open and returns closed after more than maxHole: no tap is guessed
        do {
            let valley = 5.5 / 2.5
            let samples = taps().map { s in s.t > valley - 0.25 && s.t < valley - 0.02 ? TapSample(t: s.t, gap: nil) : s }
            let r = Tapping.analyzeTaps(samples)
            noNaN(r)
            XCTAssertEqual(r.taps, 9)
        }

        // A 0.6 s hold mid-test is one pause
        do {
            let r = Tapping.analyzeTaps(join(taps(n: 5), hold(0.6, 1.1), taps(n: 5)))
            noNaN(r)
            XCTAssertEqual(r.taps, 10)
            XCTAssertEqual(r.pauses, 1)
        }

        // 3 taps: numbers still come back, but counted is false
        do {
            let r = Tapping.analyzeTaps(taps(n: 3))
            noNaN(r)
            XCTAssertEqual(r.taps, 3)
            XCTAssertFalse(r.counted)
        }

        // A still hand whose reading jitters a little has no taps, however the noise falls
        for seed in UInt32(1)...20 {
            let rand = rng(seed)
            let still = (0..<300).map { i in TapSample(t: Double(i) / fps, gap: 0.6 + (rand() - 0.5) * 0.16) }
            XCTAssertEqual(Tapping.analyzeTaps(still).taps, 0, "still hand \(seed)")
        }
        // Small taps that still open well past the jitter are counted
        XCTAssertEqual(Tapping.analyzeTaps(taps(amp: { _ in 0.35 })).taps, 10)

        // No input, no hand, or a hand that never moves: zero taps, nils, no NaN
        for input in [[], hold(2, nil), hold(2, 0.5), [TapSample(t: 0, gap: .nan), TapSample(t: 0.1, gap: .infinity)]] {
            let r = Tapping.analyzeTaps(input)
            noNaN(r)
            XCTAssertEqual(r.taps, 0)
            XCTAssertFalse(r.counted)
            XCTAssertNil(r.rate)
            XCTAssertEqual(r.tapTimes, [])
        }

        // The sentences on the result screen
        XCTAssertEqual(Copy.tapSentences(result(3, rate: 2), previous: []), [Copy.tapTooFew])
        let steady = Copy.tapSentences(result(10, rate: 2.5, openingChange: -0.05), previous: [])
        XCTAssertEqual(steady[0], "10 taps in 3.6 seconds: 2.5 taps per second.")
        XCTAssertEqual(steady[1], "Your finger opening stayed about the same size.")
        XCTAssertEqual(steady.count, 2)
        let shrunk = Copy.tapSentences(result(10, rate: 2.5, openingChange: -0.25, pauses: 2), previous: [result(10, rate: 2), result(10, rate: 2)])
        XCTAssertEqual(shrunk[1], "Your finger opening got 25% smaller from your first taps to your last.")
        XCTAssertEqual(shrunk[2], "2 pauses that were longer than your usual rhythm.")
        XCTAssertEqual(shrunk[3], "Compared with your last 2 tries with this hand: faster.")
        let one = Copy.tapSentences(result(10, rate: 2, pauses: 1), previous: [result(10, rate: 2.05)])
        XCTAssertEqual(one.last, "Compared with your last try with this hand: about the same.")
        XCTAssertTrue(one.contains("1 pause that was longer than your usual rhythm."))

        print("TAPPING OK")
    }

    func testHandCheck() {
        let left = Array(repeating: "left", count: 20), right = Array(repeating: "right", count: 20)
        // Clear agreement names the hand. Frames with no guess don't count either way
        XCTAssertEqual(HandCheck.seen(left), "left")
        XCTAssertEqual(HandCheck.seen(right + ["", "", ""]), "right")
        XCTAssertEqual(HandCheck.seen(Array(left.prefix(17)) + ["right", "right", "right"]), "left")
        // Too few frames, or a mix, says nothing
        XCTAssertNil(HandCheck.seen(Array(left.prefix(14))))
        XCTAssertNil(HandCheck.seen(Array(left.prefix(10)) + Array(right.prefix(10))))
        XCTAssertNil(HandCheck.seen(Array(repeating: "", count: 40)))
        XCTAssertEqual(HandCheck.seen(Array(left.prefix(10)), minFrames: HandCheck.minFramesLive), "left")
        // Only a clear other hand is flagged
        XCTAssertEqual(HandCheck.otherHand(picked: "right", guesses: left), "left")
        XCTAssertNil(HandCheck.otherHand(picked: "left", guesses: left))
        XCTAssertNil(HandCheck.otherHand(picked: "right", guesses: Array(left.prefix(10)) + Array(right.prefix(10))))
        XCTAssertNil(HandCheck.otherHand(picked: "right", guesses: []))
        XCTAssertEqual(Copy.tapWrongHand("left", "right"),
            "That looked like your left hand, but the right hand was picked, so this test wasn't saved. Pick the hand you're using and try again.")
        print("HAND CHECK OK")
    }

    func testOlderIPads() {
        // iPad (6th and 7th generation) and the 2017 iPad Pros get the warning
        for model in ["iPad7,11", "iPad7,12", "iPad7,5", "iPad7,6", "iPad7,3", "iPad7,1"] {
            XCTAssertFalse(HandTracking.newEnough(model), model)
        }
        // iPad Pro (2018), iPad (8th generation), newer iPads, iPhones, Macs and anything unknown don't
        for model in ["iPad8,1", "iPad11,6", "iPad11,3", "iPad11,1", "iPad13,18", "iPad16,3", "iPhone11,8", "iPhone17,1", "arm64", "x86_64", "iPad", ""] {
            XCTAssertTrue(HandTracking.newEnough(model), model)
        }
        XCTAssertFalse(HandTracking.model.isEmpty)
        print("OLD IPADS OK")
    }

    func testTapStore() {
        let suite = "neurotrace-taps-check-\(UUID().uuidString)"
        let saved = Store.defaults
        Store.defaults = UserDefaults(suiteName: suite)!
        defer {
            Store.defaults.removePersistentDomain(forName: suite)
            Store.defaults = saved
        }
        XCTAssertEqual(Store.getTapTests(), [])
        let first = TapTest(ts: 1, hand: "left", result: Tapping.analyzeTaps(taps()))
        let second = TapTest(ts: 2, hand: "right", result: Tapping.analyzeTaps(taps(n: 6)))
        Store.saveTapTest(first)
        Store.saveTapTest(second)
        XCTAssertEqual(Store.getTapTests(), [first, second])
        Store.clearTapTests()
        XCTAssertEqual(Store.getTapTests(), [])
        print("TAP STORE OK")
    }
}
