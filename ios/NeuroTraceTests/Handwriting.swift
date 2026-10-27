// HANDWRITING.SWIFT MAKES MADE UP HANDWRITING FOR THE TRAIN.SWIFT TESTS
// IT DRAWS A ROW OF CURSIVE L'S OR A ROW OF LETTER SHAPES, WITH A LITTLE RANDOM WOBBLE
// A FIXED SEED GIVES THE SAME WRITING EVERY TIME

import Foundation
// Use the NeuroTraceCore module when it exists, or the app if it doesn't
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

// Makes the same random numbers from 0 to 1 for the same seed, using Mulberry32
// It follows https://stackoverflow.com/a/47593316/1036426
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

// The settings for a row of cursive l's
// n is how many loops, height is the loop height in pixels, and loopSecs is the time for each loop
// slant is how far each point leans forward for each pixel of height
// sizeVar is how much each loop's size changes at random, where 0.1 means up to 10 percent bigger or smaller
// shrinkBy is how much smaller the last loop is than the first
// liftEvery lifts the pen after that many loops, and 0 never lifts it
// floatPx moves the writing that far above the baseline
// rest is how many seconds the pen sits still before and after writing
// jerky is how much the speed swings inside each loop, from 0 to 1
// hz is how many samples there are each second, and seed sets the random numbers
struct RowOptions {
    var n = 8, height = 120.0, loopSecs = 0.7, baselineY = 300.0, x0 = 30.0, slant = 0.25, jitter = 0.3
    var sizeVar = 0.05, shrinkBy = 0.0, liftEvery = 0, floatPx = 0.0, rest = 0.0, jerky = 0.0, hz = 240.0, seed: UInt32 = 1
}

// Makes a row of cursive l's and gives back the samples and where each stroke starts
func cursiveRow(_ o: RowOptions = RowOptions()) -> (samples: [Sample], strokeStarts: [Int]) {

    // Set up the random numbers, the samples, the time step, and the starting time and x
    let rand = rng(o.seed)
    var samples: [Sample] = [], strokeStarts = [0]
    let dt = 1 / o.hz
    var t = 0.0, x = o.x0

    // Adds one sample at a point, moved a little at random by up to jitter pixels
    let point = { (px: Double, py: Double) in samples.append(Sample(t: t, x: px + (rand() - 0.5) * 2 * o.jitter, y: py + (rand() - 0.5) * 2 * o.jitter)) }

    // The line the writing sits on
    let base = o.baselineY - o.floatPx

    // Keep the pen still at the start for rest seconds
    var r = 0.0
    while r < o.rest { point(x, base); t += dt; r += dt }

    // Draw each loop
    for k in 0..<o.n {

        // Work out this loop's height, shrinking along the row and changing a little at random
        let H = o.height * (1 - o.shrinkBy * (Double(k) / Double(max(1, o.n - 1)))) * (1 + (rand() - 0.5) * 2 * o.sizeVar)

        // c is how far the loop moves forward and w is the loop's width
        let c = (0.45 * H) / (2 * Double.pi), w = 1.7 * c
        let steps = Int(jsRound(o.loopSecs * o.hz))

        // Add each sample around the loop
        for s in 0..<steps {
            let u = Double(s) / Double(steps)

            // Change the speed inside the loop while keeping the loop's total time the same
            let th = 2 * Double.pi * (u + o.jerky * sin(2 * Double.pi * 3 * u) / (2 * Double.pi * 3))
            let h = H * (1 - cos(th)) / 2
            point(x + c * th + w * sin(th) + o.slant * h, base - h)
            t += dt
        }

        // Move forward to the start of the next loop
        x += 2 * Double.pi * c

        // Lift the pen for 0.35 seconds after every liftEvery loops, except after the last one, and start a new stroke
        if o.liftEvery != 0 && (k + 1) % o.liftEvery == 0 && k < o.n - 1 {
            t += 0.35
            strokeStarts.append(samples.count)
        }
    }

    // Keep the pen still at the end for rest seconds
    r = 0
    while r < o.rest { point(x, base); t += dt; r += dt }
    return (samples: samples, strokeStarts: strokeStarts)
}

// A letter shape, its points, and whether it should count as a loop
struct Shape {
    var loop: Bool
    var pts: [[Double]]
}


// LETTER SHAPES FOR CHECKING WHAT COUNTS AS A LOOP

// Each shape is a list of points with x to the right and h going up, measured in letter heights
// Each one starts and ends on the baseline, and a smooth curve goes through the points
// Shapes with loop set to true should count as loops, and the rest should not
let shapes: [String: Shape] = [

    // A closed cursive l that goes up the right, over the top, down the left, and crosses itself
    "closedL": Shape(loop: true, pts: [[0, 0], [0.3, 0.35], [0.5, 0.75], [0.42, 1], [0.3, 0.8], [0.3, 0.4], [0.42, 0.05], [0.6, 0]]),

    // A narrow l that goes up on a slant to the stem, up the stem, and straight back down it
    "narrowL": Shape(loop: true, pts: [[0, 0], [0.22, 0.38], [0.38, 0.68], [0.41, 1], [0.4, 0.68], [0.41, 0.3], [0.45, 0.05], [0.62, 0]]),

    // Goes back down along the way it went up, a little behind it, and never crosses
    "retrace": Shape(loop: true, pts: [[0, 0], [0.25, 0.5], [0.45, 1], [0.32, 0.55], [0.2, 0.2], [0.3, 0.03], [0.55, 0]]),

    // An e that comes in low from the left, goes up and back over the top, and down behind, crossing the way in
    "eLoop": Shape(loop: true, pts: [[0, 0.25], [0.3, 0.45], [0.4, 0.8], [0.28, 1], [0.12, 0.85], [0.08, 0.45], [0.2, 0.05], [0.6, 0]]),

    // A tent with a small curl at its top
    "curl": Shape(loop: false, pts: [[0, 0], [0.3, 0.55], [0.42, 0.88], [0.5, 1], [0.58, 0.95], [0.55, 0.88], [0.48, 0.92], [0.55, 0.6], [0.75, 0]]),

    // A tooth that goes up on a slant and straight down
    "tooth": Shape(loop: false, pts: [[0, 0], [0.2, 0.45], [0.4, 1], [0.41, 0.5], [0.43, 0.08], [0.6, 0]]),

    // A spike that goes straight up and straight down, moving forward
    "spike": Shape(loop: false, pts: [[0, 0], [0.32, 1], [0.6, 0]]),

    // A round hump
    "hump": Shape(loop: false, pts: [[0, 0], [0.2, 0.75], [0.4, 1], [0.6, 0.75], [0.8, 0]]),

    // An n that goes up, across the top, and down
    "nArch": Shape(loop: false, pts: [[0, 0], [0.05, 0.9], [0.25, 1], [0.5, 0.9], [0.55, 0]]),
]

// Makes a smooth curve through the points, with perSeg points between each pair
private func catmull(_ pts: [[Double]], _ perSeg: Int) -> [[Double]] {

    // Repeat the first and last points at the ends
    let P = [pts[0]] + pts + [pts[pts.count - 1]]
    var out: [[Double]] = []

    // Go through each pair of points with the point before and the point after
    for i in stride(from: 1, to: P.count - 2, by: 1) {
        let (p0, p1, p2, p3): ([Double], [Double], [Double], [Double]) = (P[i - 1], P[i], P[i + 1], P[i + 2])
        for s in 0..<perSeg {
            let u = Double(s) / Double(perSeg), u2 = u * u, u3 = u2 * u

            // Work out x and then h with the Catmull Rom formula
            out.append([0, 1].map { (k: Int) -> Double in
                let a: Double = 2 * p1[k] + (-p0[k] + p2[k]) * u
                let b: Double = (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * u2
                let c: Double = (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * u3
                return 0.5 * (a + b + c)
            })
        }
    }

    // End on the last point
    out.append(pts[pts.count - 1])
    return out
}

// One letter in a row, by shape name, with an optional height and how far it drops below the baseline
// It can also be written as just the shape name in quotes
struct LetterSpec: ExpressibleByStringLiteral {
    var shape: String
    var height: Double? = nil
    var drop = 0.0
    init(shape: String, height: Double? = nil, drop: Double = 0) { self.shape = shape; self.height = height; self.drop = drop }
    init(stringLiteral value: String) { shape = value }
}

// The settings for a row of letters
struct LetterOptions {
    var height = 120.0, baselineY = 300.0, x0 = 30.0, slant = 0.2, speed = 3.0, jitter = 0.4, hz = 120.0
    var seed: UInt32 = 1, widthScale = 1.0
}

// Makes a row of letters on a baseline at y equal to baselineY
// height is in pixels, and drop moves a letter's bottom that many pixels below the baseline
// slant leans every letter forward, speed is in letter heights per second, jitter is in pixels, and hz is samples per second
func letterRow(_ letters: [LetterSpec], _ o: LetterOptions = LetterOptions()) -> (samples: [Sample], strokeStarts: [Int]) {

    // Set up the random numbers, the samples, and the starting x and time
    let rand = rng(o.seed)
    var samples: [Sample] = []
    var x = o.x0, t = 0.0

    // Draw each letter
    for spec in letters {

        // Look up the shape, stretch it sideways by widthScale, and make a smooth curve through it
        let shape = spec.shape, H = spec.height ?? o.height, drop = spec.drop
        let pts = shapes[shape]!.pts.map { p in [p[0] * o.widthScale, p[1]] }
        let curve = catmull(pts, 24)

        // Walk along the curve
        for i in 0..<curve.count {
            let px = curve[i][0], ph = curve[i][1]

            // Move the time forward by the distance from the last point divided by the speed
            if i != 0 {
                let qx = curve[i - 1][0], qh = curve[i - 1][1]
                t += hypot(px - qx, ph - qh) / o.speed
            }

            // Add a sample once enough time has passed, leaning it forward and moving it a little at random
            if samples.isEmpty || t - samples[samples.count - 1].t >= 1 / o.hz {
                samples.append(Sample(t: t, x: x + (px + o.slant * ph) * H + (rand() - 0.5) * 2 * o.jitter, y: o.baselineY + drop - ph * H + (rand() - 0.5) * 2 * o.jitter))
            }
        }

        // Move forward to the end of the letter
        x += pts[pts.count - 1][0] * H
    }
    return (samples: samples, strokeStarts: [0])
}

// Turns writing into what a mouse would report, with whole pixel positions and a sample for each pixel it moves
// Two strokes then often cross by sharing a pixel
func mouseLike(_ writing: (samples: [Sample], strokeStarts: [Int])) -> (samples: [Sample], strokeStarts: [Int]) {
    let samples = writing.samples
    let lifts = Set(writing.strokeStarts)
    var out: [Sample] = [], starts: [Int] = []

    // Go through each sample, starting a new stroke where the pen was lifted
    for i in 0..<samples.count {
        let b = samples[i], lift = lifts.contains(i), a = lift ? b : samples[i - 1]
        if lift { starts.append(out.count) }

        // Split the move from the last sample into one step per pixel
        let n = max(1, Int(ceil(hypot(b.x - a.x, b.y - a.y))))
        for k in stride(from: lift ? n : 1, through: n, by: 1) {

            // Round each step to whole pixels, and add it only if it lands on a new pixel
            let p = Sample(t: a.t + ((b.t - a.t) * Double(k)) / Double(n), x: jsRound(a.x + ((b.x - a.x) * Double(k)) / Double(n)), y: jsRound(a.y + ((b.y - a.y) * Double(k)) / Double(n)))
            let q = out.last
            if lift || q == nil || q!.x != p.x || q!.y != p.y { out.append(p) }
        }
    }
    return (samples: out, strokeStarts: starts)
}
