// checks Train.swift: the level rule and the big-writing measures, on
// made-up drawings with known answers. run with the other tests (⌘U)

import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

private typealias LevelState = Train.LevelState

private let levels = Train.exercises["big-writing"]!.levels.count
private let hit = (counted: true, hit: true), miss = (counted: true, hit: false), skip = (counted: false, hit: false)

// a row of n loops, each `height` px tall above a baseline at y = 300, one
// loop every `secs` seconds, sampled at 120 Hz. `wobble` adds a fast shake.
// closed: false draws humps that go up and straight back down instead.
private func loops(n: Int = 8, height: Double = 120, secs: Double = 0.8, wobble: Double = 0, closed: Bool = true) -> [Sample] {
    var samples: [Sample] = []
    let dt = 1.0 / 120, total = Double(n) * secs, back = closed ? (1.7 * 600) / Double(n) / (2 * Double.pi) : 0
    var t = 0.0
    while t <= total + 1e-9 {
        let phase = (t / secs).truncatingRemainder(dividingBy: 1)
        let shake = wobble * sin(2 * Double.pi * 9 * t)
        samples.append(Sample(
            t: t,
            x: 20 + (t / total) * 600 + back * sin(2 * Double.pi * phase),
            y: 300 - height * (0.5 - 0.5 * cos(2 * Double.pi * phase)) + shake
        ))
        t += dt
    }
    return samples
}
private let geo = (baselineY: 300.0, targetPx: 120.0)

// following a path at a steady speed. offset: px off the path, sideways.
// warp: speed swings (0..1), cycles of them over the whole path - a real hand
// speeds up and slows down a few times a turn. secs: time to trace the whole path.
private func follow(_ path: Train.Path, secs: Double = 6, offset: Double = 0, upTo: Double = 1, warp: Double = 0.3, cycles: Double = 9, hz: Double = 240, start: Double = 0) -> [Sample] {
    var samples: [Sample] = []
    var t = 0.0
    while t <= secs * upTo {
        let u = t / secs, uw = u + warp * sin(2 * Double.pi * cycles * u) / (2 * Double.pi * cycles)
        let (x, y) = Train.pointAlong(path, (start + uw * (1 - start)) * path.length)
        samples.append(Sample(t: t, x: x + offset, y: y + offset))
        t += 1 / hz
    }
    return samples
}

final class TrainTests: XCTestCase {
    func testTrain() {
        let run = { (state: LevelState, tries: [(counted: Bool, hit: Bool)]) -> LevelState in
            tries.reduce(state) { s, t in Train.applyTry(s, t, levels).state }
        }
        let real = { (opts: RowOptions, recent: [[String: Double]]) -> Train.Outcome in
            let (samples, strokeStarts) = cursiveRow(opts)
            return Train.scoreBigWriting(samples, strokeStarts, geo, recent)
        }
        let near = { (a: Double, b: Double, tol: Double, what: String) in XCTAssertTrue(abs(a - b) <= tol, "\(what): \(a) vs \(b)") }

        // --- level rule -----------------------------------------------------------
        XCTAssertEqual(Train.hitsToLevelUp, 3)
        XCTAssertEqual(Train.missesToLevelDown, 3)
        var s = run(Train.newLevelState(), [hit, hit])
        XCTAssertEqual(s, LevelState(level: 0, hits: 2, misses: 0, last: nil))
        var r = Train.applyTry(s, hit, levels)
        XCTAssertEqual(r.change, "up")
        XCTAssertEqual(r.state, LevelState(level: 1, hits: 0, misses: 0, last: "up"))
        // hits don't have to be in a row, misses do
        s = run(LevelState(level: 1, hits: 0, misses: 0, last: nil), [miss, miss, hit])
        XCTAssertEqual(s, LevelState(level: 1, hits: 1, misses: 0, last: nil))
        r = Train.applyTry(run(LevelState(level: 1, hits: 1, misses: 0, last: nil), [miss, miss]), miss, levels)
        XCTAssertEqual(r.change, "down")
        XCTAssertEqual(r.state, LevelState(level: 0, hits: 0, misses: 0, last: "down"))
        // floor and ceiling
        s = run(Train.newLevelState(), [miss, miss, miss, miss])
        XCTAssertEqual(s.level, 0)
        s = run(LevelState(level: levels - 1, hits: 0, misses: 0, last: nil), [hit, hit, hit, hit])
        XCTAssertEqual(s.level, levels - 1)
        // a try that didn't count changes nothing
        XCTAssertEqual(Train.applyTry(LevelState(level: 2, hits: 1, misses: 2, last: nil), skip, levels).state, LevelState(level: 2, hits: 1, misses: 2, last: nil))
        // too hard today
        XCTAssertEqual(Train.tooHard(LevelState(level: 3, hits: 2, misses: 1, last: "up")), LevelState(level: 2, hits: 0, misses: 0, last: "down"))
        XCTAssertEqual(Train.tooHard(Train.newLevelState()), Train.newLevelState())

        // --- big writing ------------------------------------------------------------
        let tops = Train.findLoops(loops(), 300, 120).map { l in l.own }
        XCTAssertEqual(tops.count, 8)
        for h in tops { XCTAssertTrue(abs(h - 120) < 2, "loop top \(h)") }

        // reaching the line, nothing to compare with yet: a hit on the target alone
        let tall = Train.scoreBigWriting(loops(), [0], geo)
        XCTAssertTrue(tall.counted && tall.reachedTarget && tall.hit, "\(tall)")
        XCTAssertEqual(tall.measures["reached"], 8)
        XCTAssertTrue(abs(tall.measures["pace"]! - 1.25) < 0.05, "pace \(tall.measures["pace"]!)")
        XCTAssertTrue(tall.measures["peaksPerLoop"]! >= 1.5 && tall.measures["peaksPerLoop"]! <= 2.5, "peaks/loop \(tall.measures["peaksPerLoop"]!)")
        XCTAssertEqual(Train.compareRecent(tall.measures, []).pace, nil)

        // half-height loops miss the line
        let small = Train.scoreBigWriting(loops(height: 60), [0], geo)
        XCTAssertTrue(small.counted && !small.reachedTarget && !small.hit)
        XCTAssertEqual(small.measures["reached"], 0)

        // three loops is too short to judge
        XCTAssertEqual(Train.scoreBigWriting(loops(n: 3), [0], geo).counted, false)

        // the trade-off: the same tall loops at half the pace reach the line but don't count
        let recent = [tall.measures, tall.measures, tall.measures]
        let slow = Train.scoreBigWriting(loops(secs: 1.6), [0], geo, recent)
        XCTAssertTrue(slow.reachedTarget && slow.slower && !slow.hit, "\(slow.vs)")
        XCTAssertTrue(abs(slow.vs.pace! + 0.5) < 0.05)

        // a shaky try at the same pace reaches the line but doesn't count either
        let shaky = Train.scoreBigWriting(loops(wobble: 6), [0], geo, recent)
        XCTAssertTrue(shaky.reachedTarget && shaky.shakier && !shaky.hit, "\(shaky.vs)")

        // the same try again compares as unchanged
        let same = Train.scoreBigWriting(loops(), [0], geo, recent)
        XCTAssertTrue(same.hit && abs(same.vs.pace!) < 0.01 && abs(same.vs.smoothness!) < 0.01)

        // loops shrinking along the row show up as a negative shrink
        let nine = loops(n: 9)
        let shrinking = nine.map { p in Sample(t: p.t, x: p.x, y: 300 - (300 - p.y) * (1 - 0.4 * (p.t / nine[nine.count - 1].t))) }
        XCTAssertTrue(Train.scoreBigWriting(shrinking, [0], geo).measures["shrink"]! < -0.2)

        // --- realistic handwriting (tools/handwriting.mjs) ----------------------------
        // slanted cursive l's sampled like an Apple Pencil. each case states what a
        // person would do and what the score must still get right.
        let plain = real(RowOptions(), [])
        XCTAssertEqual(plain.measures["loops"], 8)
        near(plain.measures["size"]!, 1, 0.05, "size")
        near(plain.measures["pace"]!, 1 / 0.7, 0.05, "pace")
        XCTAssertTrue(plain.hit)
        XCTAssertEqual(plain.marks!.count, 8)
        XCTAssertTrue(plain.marks!.allSatisfy { m in m.reached && m.x.isFinite && m.y.isFinite })

        // every loop is found whatever the size, speed, slant, pen lifts or sampling rate
        for opts in [RowOptions(height: 240), RowOptions(height: 60), RowOptions(height: 36), RowOptions(loopSecs: 0.45), RowOptions(loopSecs: 1.2), RowOptions(slant: 0),
            RowOptions(slant: 0.6), RowOptions(liftEvery: 3), RowOptions(liftEvery: 1), RowOptions(jitter: 1.5), RowOptions(n: 12), RowOptions(hz: 60), RowOptions(seed: 2), RowOptions(seed: 3)] {
            XCTAssertEqual(real(opts, []).measures["loops"], Double(opts.n), "\(opts)")
        }

        // resting the Pencil for a second before and after isn't slow writing
        near(real(RowOptions(rest: 1), []).measures["pace"]!, 1 / 0.7, 0.05, "pace with the pen resting")

        // small loops are a miss, not "too few loops to count"
        let tiny = real(RowOptions(height: 36), [])
        XCTAssertTrue(tiny.counted && !tiny.reachedTarget)
        near(tiny.measures["size"]!, 0.3, 0.03, "small loops' size")

        // writing a little above the baseline: size is measured from the writing's own bottom
        near(real(RowOptions(floatPx: 25), []).measures["size"]!, 1, 0.05, "size above the baseline")
        // small loops written up near the line don't touch it
        let perched = real(RowOptions(height: 50, floatPx: 70), [])
        XCTAssertTrue(perched.counted && perched.measures["reached"] == 0 && !perched.reachedTarget)
        // loops started above the baseline have to be nearly full size: 75% or 80% of the gap misses, 90% reaches
        let floating = { (own: Double, lift: Double) in
            Train.scoreBigWriting(loops(height: 120 * own).map { p in Sample(t: p.t, x: p.x, y: p.y - 120 * lift) }, [0], geo)
        }
        XCTAssertFalse(floating(0.75, 0.2).reachedTarget)
        XCTAssertFalse(floating(0.8, 0.15).reachedTarget)
        XCTAssertTrue(floating(0.9, 0.05).reachedTarget)

        // a row that shrinks along the line says so
        XCTAssertTrue(real(RowOptions(shrinkBy: 0.4), []).measures["shrink"]! < -0.25)

        // size and speed alone don't change smoothness; stop-start writing does
        for opts in [RowOptions(height: 60), RowOptions(height: 240), RowOptions(loopSecs: 0.45), RowOptions(loopSecs: 1.2)] {
            near(real(opts, []).measures["peaksPerLoop"]!, plain.measures["peaksPerLoop"]!, 0.25, "smoothness \(opts)")
        }
        let history = [plain.measures, real(RowOptions(seed: 2), []).measures, real(RowOptions(seed: 3), []).measures]
        let jerky = real(RowOptions(jerky: 0.6), history)
        XCTAssertTrue(jerky.reachedTarget && jerky.shakier && !jerky.hit, "\(jerky.vs)")
        // bigger at the same pace after smaller tries: a hit, the goal of the exercise
        let bigger = real(RowOptions(height: 160), history)
        XCTAssertTrue(bigger.hit && !bigger.slower && !bigger.shakier, "\(bigger.vs)")
        // bigger by slowing down: reaches the line but doesn't count
        let slowBig = real(RowOptions(height: 160, loopSecs: 1.1), history)
        XCTAssertTrue(slowBig.reachedTarget && slowBig.slower && !slowBig.hit, "\(slowBig.vs)")

        // --- steady tracing -----------------------------------------------------------
        let spiral = Train.tracingPath(340, 340)
        XCTAssertTrue(abs(spiral.radius - 146) < 1e-9)
        let onLine = Train.scoreTracing(follow(spiral), [0], spiral)
        XCTAssertTrue(onLine.counted && onLine.reachedTarget && onLine.hit, "\(onLine.measures)")
        XCTAssertEqual(onLine.measures["cover"], 1)
        XCTAssertTrue(onLine.measures["accuracy"]! < 0.01)
        near(onLine.measures["pace"]!, spiral.length / spiral.radius / 6, 0.05, "tracing pace")
        // wandering ~10% of the radius off the guide is a miss
        let wander = Train.scoreTracing(follow(spiral, offset: 11), [0], spiral)
        XCTAssertTrue(wander.counted && !wander.reachedTarget, "\(wander.measures)")
        // a third of the spiral is too short to judge
        XCTAssertEqual(Train.scoreTracing(follow(spiral, upTo: 0.3), [0], spiral).counted, false)
        // accurate but twice as slow as recent tries doesn't count
        let traceHistory = [onLine.measures, onLine.measures, onLine.measures]
        let slowTrace = Train.scoreTracing(follow(spiral, secs: 12), [0], spiral, traceHistory)
        XCTAssertTrue(slowTrace.reachedTarget && slowTrace.slower && !slowTrace.hit, "\(slowTrace.vs)")
        // accurate at the same pace but stop-start doesn't count either
        let jerkyTrace = Train.scoreTracing(follow(spiral, warp: 0.7, cycles: 27), [0], spiral, traceHistory)
        XCTAssertTrue(jerkyTrace.reachedTarget && jerkyTrace.shakier && !jerkyTrace.hit, "\(jerkyTrace.vs)")
        XCTAssertEqual(Train.traceTurns, 3)

        // --- rhythm ------------------------------------------------------------------
        let wave = Train.rhythmPath(340, 226)
        near(wave.beatLength * Train.rhythmBeats, wave.length, 1e-6, "beats tile the wave")
        // beat boundaries land on tops and bottoms
        near(Train.pointAlong(wave, wave.beatLength).1, 226 / 2 - 0.3 * 226, 1, "beat 1 ends at a top")
        let beatSec = 60.0 / 60
        let inStep = Train.scoreRhythm(follow(wave, secs: Train.rhythmBeats * beatSec), [0], wave, (beatSec: beatSec, penOffset: 0))
        XCTAssertTrue(inStep.counted && inStep.reachedTarget && inStep.hit, "\(inStep.measures)")
        XCTAssertTrue(inStep.measures["lag"]! < 0.05 && abs(inStep.measures["lead"]!) < 0.05)
        XCTAssertEqual(inStep.vs.pace, nil)
        // setting off a beat late and staying a beat behind is a miss
        let late = Train.scoreRhythm(follow(wave, secs: Train.rhythmBeats * beatSec), [0], wave, (beatSec: beatSec, penOffset: 1))
        XCTAssertTrue(late.counted && !late.reachedTarget, "\(late.measures)")
        near(late.measures["lead"]!, -1, 0.1, "a beat behind")
        // rushing to the end in half the time is a miss too
        let rushed = Train.scoreRhythm(follow(wave, secs: Train.rhythmBeats * beatSec / 2), [0], wave, (beatSec: beatSec, penOffset: 0))
        XCTAssertTrue(!rushed.reachedTarget && rushed.measures["lead"]! > 1, "\(rushed.measures)")
        // waiting on the start point through the count-in doesn't hurt
        let waited = follow(wave, secs: Train.rhythmBeats * beatSec)
        let resting = (0..<240).map { i in Sample(t: Double(i) / 240, x: waited[0].x, y: waited[0].y) }
        let withRest = resting + waited.map { p in Sample(t: p.t + 1, x: p.x, y: p.y) }
        XCTAssertTrue(Train.scoreRhythm(withRest, [0], wave, (beatSec: beatSec, penOffset: -1)).hit)
        // keeping up by speeding up and slowing down along the wave isn't shaky; a
        // line that wobbles across the wave is
        let shaken = { (samples: [Sample], px: Double) in samples.map { p in Sample(t: p.t, x: p.x, y: p.y + px * sin(2 * Double.pi * 5 * p.t)) } }
        let steadyBeat = Train.scoreRhythm(shaken(follow(wave, secs: Train.rhythmBeats * beatSec), 1), [0], wave, (beatSec: beatSec, penOffset: 0))
        let beatHistory = [steadyBeat.measures, steadyBeat.measures, steadyBeat.measures]
        let surging = Train.scoreRhythm(shaken(follow(wave, secs: Train.rhythmBeats * beatSec, warp: 0.8, cycles: 24), 1), [0], wave, (beatSec: beatSec, penOffset: 0), beatHistory)
        XCTAssertTrue(surging.hit && !surging.shakier, "\([surging.measures]) \(surging.vs)")
        XCTAssertTrue(surging.measures["peaksPerBeat"]! > 1.5 * steadyBeat.measures["peaksPerBeat"]!, "surges add speed peaks")
        let wobbly = Train.scoreRhythm(shaken(follow(wave, secs: Train.rhythmBeats * beatSec), 3), [0], wave, (beatSec: beatSec, penOffset: 0), beatHistory)
        XCTAssertTrue(wobbly.reachedTarget && wobbly.shakier && !wobbly.hit, "\([wobbly.measures]) \(wobbly.vs)")
        // tries saved before wobble was measured are left out of the comparison
        XCTAssertEqual(Train.scoreRhythm(shaken(follow(wave, secs: Train.rhythmBeats * beatSec), 3), [0], wave, (beatSec: beatSec, penOffset: 0),
            [["peaksPerBeat": 3], ["peaksPerBeat": 3]]).vs.smoothness, nil)

        // --- hand skills ---------------------------------------------------------------
        XCTAssertEqual(Train.targetRadius(96, 0), 48)
        XCTAssertEqual(Train.targetRadius(96, Train.shrinkSecs / 2), 24)
        XCTAssertEqual(Train.targetRadius(96, Train.shrinkSecs + 1), 0)
        let all = (0..<Train.targets).map { i in Train.TargetResult(caught: true, ms: Double(500 + i)) }
        let tapped = Train.scoreTargets(all, 0)
        XCTAssertTrue(tapped.counted && tapped.hit && tapped.measures["caught"] == Double(Train.targets) && tapped.measures["reactionMs"] == 507)
        let some = all.enumerated().map { (i, r) in Train.TargetResult(caught: i % 3 != 0, ms: r.ms) } // 10 of 15
        XCTAssertTrue(Train.scoreTargets(some, 4).counted && !Train.scoreTargets(some, 4).hit)
        XCTAssertTrue(!Train.scoreTargets(Array(all.prefix(5)), 0).counted)

        // --- loopholes (found by hand on Oct 5) ---------------------------------------
        // humps that reach the line but never close into a loop are attempts that miss
        let humps = Train.scoreBigWriting(loops(closed: false), [0], geo)
        XCTAssertTrue(humps.counted && humps.measures["loops"] == 8 && humps.measures["reached"] == 0 && humps.measures["open"] == 8)
        XCTAssertTrue(!humps.reachedTarget && humps.marks!.allSatisfy { m in !m.reached })
        XCTAssertEqual(plain.measures["open"], 0)
        // one spike in a row of loops is one miss, marked with a ring
        func joinRows(_ rows: [Sample]...) -> (samples: [Sample], strokeStarts: [Int]) {
            var samples: [Sample] = []
            let strokeStarts = [0]
            var dx = 0.0, dt = 0.0
            for row in rows {
                let x0 = row[0].x, t0 = row[0].t
                for p in row { samples.append(Sample(t: p.t - t0 + dt, x: p.x - x0 + dx, y: p.y)) }
                dx = samples[samples.count - 1].x
                dt = samples[samples.count - 1].t + 1.0 / 240
            }
            return (samples: samples, strokeStarts: strokeStarts)
        }
        let row = { (n: Int) in cursiveRow(RowOptions(n: n, sizeVar: 0)).samples }
        let spiked = joinRows(row(4), loops(n: 1, closed: false), row(3))
        let withSpike = Train.scoreBigWriting(spiked.samples, spiked.strokeStarts, geo)
        XCTAssertEqual(withSpike.measures["loops"], 8)
        XCTAssertEqual(withSpike.measures["reached"], 7)
        XCTAssertEqual(withSpike.measures["open"], 1)
        // small bumps between tall loops count as letters that fell short, not as nothing
        let bumpy = joinRows(row(4), cursiveRow(RowOptions(n: 2, height: 30, sizeVar: 0)).samples, row(2))
        let withBumps = Train.scoreBigWriting(bumpy.samples, bumpy.strokeStarts, geo)
        XCTAssertEqual(withBumps.measures["loops"], 8, "\(withBumps.measures)")
        XCTAssertEqual(withBumps.measures["reached"], 6)
        // a row that shrinks to tiny letters at the end keeps every letter
        let fading = joinRows(row(5), cursiveRow(RowOptions(n: 3, height: 25, sizeVar: 0)).samples)
        let shrunk = Train.scoreBigWriting(fading.samples, fading.strokeStarts, geo)
        XCTAssertEqual(shrunk.measures["loops"], 8)
        XCTAssertTrue(shrunk.measures["shrink"]! < -0.5, "shrink \(shrunk.measures["shrink"]!)")
        // a mouse reports whole pixels, so strokes often cross by sharing one: closed
        // loops written with a mouse still count
        let byMouse = mouseLike(cursiveRow())
        XCTAssertEqual(Train.scoreBigWriting(byMouse.samples, byMouse.strokeStarts, geo).measures["reached"], 8)
        // every letter shape, written with a pen and with a mouse: narrow l's, l's
        // written back down over themselves and e's count; spikes, teeth, humps, n's
        // and tents with a small curl on top don't
        for (shape, spec) in shapes {
            let loop = spec.loop
            for slant in [0, 0.3] {
                let pen = letterRow(Array(repeating: LetterSpec(shape: shape), count: 8), LetterOptions(height: 132, slant: slant))
                for (input, w) in [("pen", pen), ("mouse", mouseLike(pen))] {
                    let m = Train.scoreBigWriting(w.samples, w.strokeStarts, geo).measures
                    XCTAssertEqual(m["loops"], 8, "\(shape) \(input) slant \(slant)")
                    XCTAssertEqual(m["reached"], loop ? 8 : 0, "\(shape) \(input) slant \(slant)")
                    XCTAssertEqual(m["open"], loop ? 0 : 8, "\(shape) \(input) slant \(slant)")
                }
            }
        }
        // loops that dip well below the baseline don't count, nor does the letter
        // that starts from the bottom of one
        let dipped = letterRow(Array(repeating: LetterSpec(shape: "closedL", drop: 60), count: 3) + Array(repeating: "closedL", count: 5), LetterOptions(height: 132))
        let withDips = Train.scoreBigWriting(dipped.samples, dipped.strokeStarts, geo).measures
        XCTAssertEqual(withDips["loops"], 8)
        XCTAssertEqual(withDips["reached"], 4)
        XCTAssertEqual(withDips["below"], 4)
        // going up and down over the same spot is one letter, not a row
        let inPlace = (0..<400).map { i in Sample(t: Double(i) / 120, x: 300 + 0.05 * Double(i), y: 300 - 66 * (1 - cos((2 * Double.pi * Double(i)) / 40))) }
        let scribble = Train.scoreBigWriting(inPlace, [0], geo)
        XCTAssertEqual(scribble.measures["loops"], 1)
        XCTAssertTrue(!scribble.counted && !scribble.hit)

        // tapping everywhere isn't catching: 15 caught with 163 stray taps is a miss
        XCTAssertTrue(!Train.scoreTargets(all, 163).reachedTarget)
        XCTAssertTrue(Train.scoreTargets(all, 3).hit && !Train.scoreTargets(all, 4).hit)

        print("TRAIN OK")
    }
}
