// simulated handwriting for testing Train.swift (a row of cursive l's).
// uses 240 Hz by default with small random jitter. a fixed seed makes
// the generated data repeatable.

import Foundation
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

// Mulberry32: repeatable random numbers from a seed. This was adapted from https://stackoverflow.com/a/47593316/1036426
func rng(_ seed: UInt32) -> () -> Double {
    var a = seed
    return {
        a = a &+ 0x6d2b79f5
        var t = a
        t = (t ^ (t >> 15)) &* (t | 1)
        t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
        return Double(t ^ (t >> 14)) / 4294967296
    }
}

// height: loop height in px. loopSecs: time per loop. slant: forward lean
// (x shift per px of height). sizeVar: random loop-to-loop size change
// (0.1 = +-10%). shrinkBy: the last loop is this much smaller than the first.
// liftEvery: lift the pen after every k loops. floatPx: writes this far above
// the drawn baseline. rest: seconds the pen sits still before and after.
// jerky: speed swings within each loop (stop-start movement), 0..1.
struct RowOptions {
    var n = 8, height = 120.0, loopSecs = 0.7, baselineY = 300.0, x0 = 30.0, slant = 0.25, jitter = 0.3
    var sizeVar = 0.05, shrinkBy = 0.0, liftEvery = 0, floatPx = 0.0, rest = 0.0, jerky = 0.0, hz = 240.0, seed: UInt32 = 1
}

func cursiveRow(_ o: RowOptions = RowOptions()) -> (samples: [Sample], strokeStarts: [Int]) {
    let rand = rng(o.seed)
    var samples: [Sample] = [], strokeStarts = [0]
    let dt = 1 / o.hz
    var t = 0.0, x = o.x0
    let point = { (px: Double, py: Double) in samples.append(Sample(t: t, x: px + (rand() - 0.5) * 2 * o.jitter, y: py + (rand() - 0.5) * 2 * o.jitter)) }
    let base = o.baselineY - o.floatPx
    var r = 0.0
    while r < o.rest { point(x, base); t += dt; r += dt }
    for k in 0..<o.n {
        let H = o.height * (1 - o.shrinkBy * (Double(k) / Double(max(1, o.n - 1)))) * (1 + (rand() - 0.5) * 2 * o.sizeVar)
        let c = (0.45 * H) / (2 * Double.pi), w = 1.7 * c // forward advance, loop width
        let steps = Int(jsRound(o.loopSecs * o.hz))
        for s in 0..<steps {
            let u = Double(s) / Double(steps)
            // varies the speed within each loop without changing its overall duration.
            let th = 2 * Double.pi * (u + o.jerky * sin(2 * Double.pi * 3 * u) / (2 * Double.pi * 3))
            let h = H * (1 - cos(th)) / 2
            point(x + c * th + w * sin(th) + o.slant * h, base - h)
            t += dt
        }
        x += 2 * Double.pi * c
        if o.liftEvery != 0 && (k + 1) % o.liftEvery == 0 && k < o.n - 1 {
            t += 0.35 // pen in the air
            strokeStarts.append(samples.count)
        }
    }
    r = 0
    while r < o.rest { point(x, base); t += dt; r += dt }
    return (samples: samples, strokeStarts: strokeStarts)
}

struct Shape {
    var loop: Bool
    var pts: [[Double]]
}

// ---------- letter shapes, for testing what counts as a loop ----------
// each shape is a list of control points (x right, h up) in units of the
// letter's height, starting and ending on the baseline. a smooth curve runs
// through them. `loop: true` shapes should count as loops, the rest shouldn't.
let shapes: [String: Shape] = [
    // a closed cursive l: up the right, over the top, down the left, crossing.
    "closedL": Shape(loop: true, pts: [[0, 0], [0.3, 0.35], [0.5, 0.75], [0.42, 1], [0.3, 0.8], [0.3, 0.4], [0.42, 0.05], [0.6, 0]]),
    // a narrow l: up on a slant to the stem, up the stem and straight back down it.
    "narrowL": Shape(loop: true, pts: [[0, 0], [0.22, 0.38], [0.38, 0.68], [0.41, 1], [0.4, 0.68], [0.41, 0.3], [0.45, 0.05], [0.62, 0]]),
    // down along the way it went up, a little behind it, never crossing.
    "retrace": Shape(loop: true, pts: [[0, 0], [0.25, 0.5], [0.45, 1], [0.32, 0.55], [0.2, 0.2], [0.3, 0.03], [0.55, 0]]),
    // an e: in low from the left, up and back over the top, down behind, crossing the way in.
    "eLoop": Shape(loop: true, pts: [[0, 0.25], [0.3, 0.45], [0.4, 0.8], [0.28, 1], [0.12, 0.85], [0.08, 0.45], [0.2, 0.05], [0.6, 0]]),
    // a tent with a small curl at its top.
    "curl": Shape(loop: false, pts: [[0, 0], [0.3, 0.55], [0.42, 0.88], [0.5, 1], [0.58, 0.95], [0.55, 0.88], [0.48, 0.92], [0.55, 0.6], [0.75, 0]]),
    // a tooth: up on a slant, straight down.
    "tooth": Shape(loop: false, pts: [[0, 0], [0.2, 0.45], [0.4, 1], [0.41, 0.5], [0.43, 0.08], [0.6, 0]]),
    // a spike: straight up and straight down, forward.
    "spike": Shape(loop: false, pts: [[0, 0], [0.32, 1], [0.6, 0]]),
    // a round hump.
    "hump": Shape(loop: false, pts: [[0, 0], [0.2, 0.75], [0.4, 1], [0.6, 0.75], [0.8, 0]]),
    // an n: up, across the top, down.
    "nArch": Shape(loop: false, pts: [[0, 0], [0.05, 0.9], [0.25, 1], [0.5, 0.9], [0.55, 0]]),
]

private func catmull(_ pts: [[Double]], _ perSeg: Int) -> [[Double]] {
    let P = [pts[0]] + pts + [pts[pts.count - 1]]
    var out: [[Double]] = []
    for i in stride(from: 1, to: P.count - 2, by: 1) {
        let (p0, p1, p2, p3): ([Double], [Double], [Double], [Double]) = (P[i - 1], P[i], P[i + 1], P[i + 2])
        for s in 0..<perSeg {
            let u = Double(s) / Double(perSeg), u2 = u * u, u3 = u2 * u
            // uniform Catmull-Rom interpolation through the control points.
            out.append([0, 1].map { (k: Int) -> Double in
                let a: Double = 2 * p1[k] + (-p0[k] + p2[k]) * u
                let b: Double = (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * u2
                let c: Double = (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * u3
                return 0.5 * (a + b + c)
            })
        }
    }
    out.append(pts[pts.count - 1])
    return out
}

struct LetterSpec: ExpressibleByStringLiteral {
    var shape: String
    var height: Double? = nil
    var drop = 0.0
    init(shape: String, height: Double? = nil, drop: Double = 0) { self.shape = shape; self.height = height; self.drop = drop }
    init(stringLiteral value: String) { shape = value }
}

struct LetterOptions {
    var height = 120.0, baselineY = 300.0, x0 = 30.0, slant = 0.2, speed = 3.0, jitter = 0.4, hz = 120.0
    var seed: UInt32 = 1, widthScale = 1.0
}

// a row of letters on a baseline at y = baselineY. letters: list of shape
// names (or { shape, height, drop }). height in px; drop moves the letter's
// base below the baseline (px). slant leans every letter forward (x per unit
// height). speed in letter-heights per second; jitter in px; sampled at hz.
func letterRow(_ letters: [LetterSpec], _ o: LetterOptions = LetterOptions()) -> (samples: [Sample], strokeStarts: [Int]) {
    let rand = rng(o.seed)
    var samples: [Sample] = []
    var x = o.x0, t = 0.0
    for spec in letters {
        let shape = spec.shape, H = spec.height ?? o.height, drop = spec.drop
        let pts = shapes[shape]!.pts.map { p in [p[0] * o.widthScale, p[1]] }
        let curve = catmull(pts, 24)
        for i in 0..<curve.count {
            let px = curve[i][0], ph = curve[i][1]
            if i != 0 {
                let qx = curve[i - 1][0], qh = curve[i - 1][1]
                t += hypot(px - qx, ph - qh) / o.speed
            }
            if samples.isEmpty || t - samples[samples.count - 1].t >= 1 / o.hz {
                samples.append(Sample(t: t, x: x + (px + o.slant * ph) * H + (rand() - 0.5) * 2 * o.jitter, y: o.baselineY + drop - ph * H + (rand() - 0.5) * 2 * o.jitter))
            }
        }
        x += pts[pts.count - 1][0] * H
    }
    return (samples: samples, strokeStarts: [0])
}

// the same writing as a mouse reports it: whole-pixel positions, a sample each
// time it moves a pixel. two strokes then often cross by sharing a pixel
// rather than passing through each other.
func mouseLike(_ writing: (samples: [Sample], strokeStarts: [Int])) -> (samples: [Sample], strokeStarts: [Int]) {
    let samples = writing.samples
    let lifts = Set(writing.strokeStarts)
    var out: [Sample] = [], starts: [Int] = []
    for i in 0..<samples.count {
        let b = samples[i], lift = lifts.contains(i), a = lift ? b : samples[i - 1]
        if lift { starts.append(out.count) }
        let n = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y))))
        for k in stride(from: lift ? n : 1, through: n, by: 1) {
            let p = Sample(t: a.t + ((b.t - a.t) * Double(k)) / Double(n), x: jsRound(a.x + ((b.x - a.x) * Double(k)) / Double(n)), y: jsRound(a.y + ((b.y - a.y) * Double(k)) / Double(n)))
            let q = out.last
            if lift || q == nil || q!.x != p.x || q!.y != p.y { out.append(p) }
        }
    }
    return (samples: out, strokeStarts: starts)
}
