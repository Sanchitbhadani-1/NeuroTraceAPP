import Foundation

// Training exercise levels, the level rule and what gets measured on every try.
// Mihir's app/train.js does all of it, called through JSCore. This file is the
// Swift shapes of what train.js takes and gives back.

enum Train {

    struct Exercise: Decodable {
        var built: Bool
        var levels: [Double]
    }

    struct LevelState: Codable, Equatable {
        var level: Int
        var hits: Int
        var misses: Int
        var last: String?
    }

    struct Vs: Codable, Equatable {
        var pace: Double?
        var smoothness: Double?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pace, forKey: .pace)
            try c.encode(smoothness, forKey: .smoothness)
        }
    }

    struct LoopMark: Equatable, Decodable {
        var x: Double
        var y: Double
        var reached: Bool
    }

    struct Outcome: Decodable {
        var counted: Bool
        var reachedTarget: Bool
        var slower: Bool
        var shakier: Bool
        var hit: Bool
        var measures: [String: Double]
        var vs: Vs
        var marks: [LoopMark]? = nil
        var limitPx: Double? = nil
    }

    struct Loop: Decodable {
        var i: Int
        var top: Double
        var own: Double
        var bottom: Double
        var closed: Bool
        var back: Double?
        var loop: Bool
        var x: Double
        var y: Double
    }

    // A path to follow. ref is the same path kept in the JavaScript, so it isn't sent again every frame
    struct Path: Codable {
        var x: [Double]
        var y: [Double]
        var s: [Double]
        var length: Double
        var radius: Double = 0
        var height: Double = 0
        var beatLength: Double = 0
        var ref: Int? = nil

        init(x: [Double], y: [Double], s: [Double], length: Double, radius: Double = 0, height: Double = 0, beatLength: Double = 0) {
            self.x = x
            self.y = y
            self.s = s
            self.length = length
            self.radius = radius
            self.height = height
            self.beatLength = beatLength
        }

        enum CodingKeys: String, CodingKey {
            case x, y, s, length, radius, height, beatLength
        }

        // Only spirals have a radius and only waves have a height and beat length
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            x = try c.decode([Double].self, forKey: .x)
            y = try c.decode([Double].self, forKey: .y)
            s = try c.decode([Double].self, forKey: .s)
            length = try c.decode(Double.self, forKey: .length)
            radius = try c.decodeIfPresent(Double.self, forKey: .radius) ?? 0
            height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 0
            beatLength = try c.decodeIfPresent(Double.self, forKey: .beatLength) ?? 0
        }

        // The kept copy when there is one, otherwise the path itself
        var arg: any Encodable {
            if let ref { return JSArg.kept(ref) }
            return self
        }
    }

    struct TargetResult: Codable, Equatable {
        var caught: Bool
        var ms: Double?

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(caught, forKey: .caught)
            try c.encode(ms, forKey: .ms)
        }
    }

    // the level rule. hit the target 3 times at a level to move up, miss 3 times in
    // a row to move back one, and "too hard today" drops one level whenever asked
    static let hitsToLevelUp: Int = JSCore.must("train.HITS_TO_LEVEL_UP")
    static let missesToLevelDown: Int = JSCore.must("train.MISSES_TO_LEVEL_DOWN")

    // each exercise's levels, easy to hard. exercises with built false show in the
    // Training tab but can't be opened yet
    static let exercises: [String: Exercise] = JSCore.must("train.EXERCISES")

    // level is an index into the exercise's levels (0 is Level 1)
    static func newLevelState() -> LevelState { JSCore.must("train.newLevelState") }

    private struct Judged: Encodable {
        var counted: Bool
        var hit: Bool
    }

    private struct Applied: Decodable {
        var state: LevelState
        var change: String?
    }

    // a judged try gives the next level state. a try that didn't count changes nothing
    static func applyTry(_ state: LevelState, _ judged: (counted: Bool, hit: Bool), _ levelCount: Int) -> (state: LevelState, change: String?) {
        let out: Applied = JSCore.must("train.applyTry", state, Judged(counted: judged.counted, hit: judged.hit), levelCount)
        return (state: out.state, change: out.change)
    }

    // "too hard today" is one level down straight away, with no penalty. Level 1 stays
    static func tooHard(_ state: LevelState) -> LevelState { JSCore.must("train.tooHard", state) }

    // ---------- big writing ----------

    // the letters in a row of loops, with how tall each one is and whether it's shaped like a loop
    static func findLoops(_ samples: [Sample], _ baselineY: Double, _ targetPx: Double, _ strokeStarts: [Int] = [0]) -> [Loop] {
        JSCore.must("train.findLoops", samples.forJS, baselineY, targetPx, strokeStarts)
    }

    // pace and smoothness against the median of recent counted tries, as fractions (0.1 is 10% more)
    static func compareRecent(_ measures: [String: Double], _ recent: [[String: Double]], _ peaksKey: String = "peaksPerLoop") -> Vs {
        JSCore.must("train.compareRecent", measures, recent, peaksKey)
    }

    private struct Geometry: Encodable {
        var baselineY: Double
        var targetPx: Double
    }

    // geometry is the baseline and the target height in points. recent is the measures of the
    // person's recent counted tries at this exercise, newest first
    static func scoreBigWriting(_ samples: [Sample], _ strokeStarts: [Int], _ geometry: (baselineY: Double, targetPx: Double), _ recent: [[String: Double]] = []) -> Outcome {
        JSCore.must("train.scoreBigWriting", samples.forJS, strokeStarts, Geometry(baselineY: geometry.baselineY, targetPx: geometry.targetPx), recent)
    }

    // ---------- paths to follow (steady tracing, rhythm) ----------

    // the point a distance of along down the path, in points. Runs every frame, so it uses the kept path
    static func pointAlong(_ path: Path, _ along: Double) -> (Double, Double) {
        let p: [Double] = JSCore.must("train.pointAlong", path.arg, along)
        return (p[0], p[1])
    }

    // ---------- steady tracing ----------

    static let traceTurns: Double = JSCore.must("train.TRACE_TURNS")
    // how close a hit stays to the spiral on average, as a share of its radius
    static let traceLimit: Double = JSCore.must("train.TRACE_LIMIT")

    // the spiral, centered in a w by h area, starting from the middle
    static func tracingPath(_ w: Double, _ h: Double) -> Path {
        let kept: (value: Path, ref: Int) = JSCore.mustKeep("train.tracingPath", w, h)
        var path = kept.value
        path.ref = kept.ref
        return path
    }

    static func scoreTracing(_ samples: [Sample], _ strokeStarts: [Int], _ path: Path, _ recent: [[String: Double]] = []) -> Outcome {
        JSCore.must("train.scoreTracing", samples.forJS, strokeStarts, path.arg, recent)
    }

    // ---------- rhythm ----------

    static let rhythmBeats: Double = JSCore.must("train.RHYTHM_BEATS")
    // beats counted in before the dot sets off
    static let countIn: Double = JSCore.must("train.COUNT_IN")
    // a hit keeps within this many beats of the dot on average, and this close to the wave
    static let rhythmLag: Double = JSCore.must("train.RHYTHM_LAG")
    static let rhythmNear: Double = JSCore.must("train.RHYTHM_NEAR")

    // the wave across a w by h area. beat k ends at along = k times beatLength, a top or a bottom
    static func rhythmPath(_ w: Double, _ h: Double) -> Path {
        let kept: (value: Path, ref: Int) = JSCore.mustKeep("train.rhythmPath", w, h)
        var path = kept.value
        path.ref = kept.ref
        return path
    }

    private struct Timing: Encodable {
        var beatSec: Double
        var penOffset: Double
    }

    // penOffset is the time from the dot setting off to the pen's first sample, in seconds
    // (negative if the pen was down first)
    static func scoreRhythm(_ samples: [Sample], _ strokeStarts: [Int], _ path: Path, _ timing: (beatSec: Double, penOffset: Double), _ recent: [[String: Double]] = []) -> Outcome {
        JSCore.must("train.scoreRhythm", samples.forJS, strokeStarts, path.arg, Timing(beatSec: timing.beatSec, penOffset: timing.penOffset), recent)
    }

    // ---------- hand skills, shrinking targets ----------

    static let targets: Int = JSCore.must("train.TARGETS")
    // a target shrinks from its starting size to nothing in this many seconds
    static let shrinkSecs: Double = JSCore.must("train.SHRINK_SECS")
    // a hit catches at least this share of targets, with at least this share of all taps on a circle
    static let catchShare: Double = JSCore.must("train.CATCH_SHARE")
    static let tapPrecision: Double = JSCore.must("train.TAP_PRECISION")

    // the target's radius secs after it appeared, 0 once it's gone. Runs every frame
    static func targetRadius(_ startSize: Double, _ secs: Double) -> Double {
        JSCore.must("train.targetRadius", startSize, secs)
    }

    // results has one caught and ms per target. extraTaps is taps that missed every target
    static func scoreTargets(_ results: [TargetResult], _ extraTaps: Int) -> Outcome {
        JSCore.must("train.scoreTargets", results, extraTaps)
    }
}
