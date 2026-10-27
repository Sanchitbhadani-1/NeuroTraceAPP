// TRAIN.SWIFT HOLDS THE TRAINING EXERCISE LEVELS, THE LEVEL RULE AND THE MEASURES FOR EACH TRY
// IT CALLS app/core/train.js THROUGH JSCORE
// IT HOLDS THE SWIFT TYPES FOR WHAT TRAIN.JS TAKES AND GIVES BACK

import Foundation

// Runs the training exercises in train.js
enum Train {

    // One exercise, with whether it is built and the setting for each level
    struct Exercise: Decodable {
        var built: Bool
        var levels: [Double]
    }

    // Where a person is in an exercise, with the level, hits, misses and the last change
    struct LevelState: Codable, Equatable {
        var level: Int
        var hits: Int
        var misses: Int
        var last: String?
    }

    // How a try compared with recent tries for pace and smoothness
    struct Vs: Codable, Equatable {
        var pace: Double?
        var smoothness: Double?

        // Write both fields, with null when one is missing
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pace, forKey: .pace)
            try c.encode(smoothness, forKey: .smoothness)
        }
    }

    // A mark on one loop of a big writing try, with its position and whether it reached the target
    struct LoopMark: Equatable, Decodable {
        var x: Double
        var y: Double
        var reached: Bool
    }

    // How a try went, as train.js judges it
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

    // One letter in a row of loops, with its size, its position, and whether it is shaped like a loop
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

    // A path to follow, where ref points to the same path kept in the JavaScript
    struct Path: Codable {
        var x: [Double]
        var y: [Double]
        var s: [Double]
        var length: Double
        var radius: Double = 0
        var height: Double = 0
        var beatLength: Double = 0
        var ref: Int? = nil

        // Make a path from its points and sizes
        init(x: [Double], y: [Double], s: [Double], length: Double, radius: Double = 0, height: Double = 0, beatLength: Double = 0) {
            self.x = x
            self.y = y
            self.s = s
            self.length = length
            self.radius = radius
            self.height = height
            self.beatLength = beatLength
        }

        // The JSON keys, which leave out ref
        enum CodingKeys: String, CodingKey {
            case x, y, s, length, radius, height, beatLength
        }

        // Read a path from JSON, using 0 for a missing radius, height or beat length
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

    // One target in hand skills, with whether it was caught and how many milliseconds it took
    struct TargetResult: Codable, Equatable {
        var caught: Bool
        var ms: Double?

        // Write both fields, with null when ms is missing
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(caught, forKey: .caught)
            try c.encode(ms, forKey: .ms)
        }
    }


    // LEVELS

    // How many hits move up a level, and how many misses in a row move down one
    static let hitsToLevelUp: Int = JSCore.must("train.HITS_TO_LEVEL_UP")
    static let missesToLevelDown: Int = JSCore.must("train.MISSES_TO_LEVEL_DOWN")

    // Each exercise's levels, easy to hard
    // Exercises with built set to false show in the Training tab but can't be opened
    static let exercises: [String: Exercise] = JSCore.must("train.EXERCISES")

    // Make a new level state, where level is an index into the exercise's levels and 0 is Level 1
    static func newLevelState() -> LevelState { JSCore.must("train.newLevelState") }

    // What applyTry sends to train.js about the try
    private struct Judged: Encodable {
        var counted: Bool
        var hit: Bool
    }

    // The new level state and the change train.js sends back
    private struct Applied: Decodable {
        var state: LevelState
        var change: String?
    }

    // Give back the next level state after a judged try, which stays the same if the try didn't count
    static func applyTry(_ state: LevelState, _ judged: (counted: Bool, hit: Bool), _ levelCount: Int) -> (state: LevelState, change: String?) {
        let out: Applied = JSCore.must("train.applyTry", state, Judged(counted: judged.counted, hit: judged.hit), levelCount)
        return (state: out.state, change: out.change)
    }

    // Move down one level right away for "too hard today", staying at Level 1 if already there
    static func tooHard(_ state: LevelState) -> LevelState { JSCore.must("train.tooHard", state) }


    // BIG WRITING

    // Find the letters in a row of loops, with how tall each one is and whether it is shaped like a loop
    static func findLoops(_ samples: [Sample], _ baselineY: Double, _ targetPx: Double, _ strokeStarts: [Int] = [0]) -> [Loop] {
        JSCore.must("train.findLoops", samples.forJS, baselineY, targetPx, strokeStarts)
    }

    // Compare pace and smoothness with the median of recent counted tries, as fractions where 0.1 is 10% more
    static func compareRecent(_ measures: [String: Double], _ recent: [[String: Double]], _ peaksKey: String = "peaksPerLoop") -> Vs {
        JSCore.must("train.compareRecent", measures, recent, peaksKey)
    }

    // The baseline and the target height sent to train.js
    private struct Geometry: Encodable {
        var baselineY: Double
        var targetPx: Double
    }

    // Judge a big writing try
    // geometry is the baseline and the target height in points, and recent is the measures of recent counted tries, newest first
    static func scoreBigWriting(_ samples: [Sample], _ strokeStarts: [Int], _ geometry: (baselineY: Double, targetPx: Double), _ recent: [[String: Double]] = []) -> Outcome {
        JSCore.must("train.scoreBigWriting", samples.forJS, strokeStarts, Geometry(baselineY: geometry.baselineY, targetPx: geometry.targetPx), recent)
    }


    // PATHS TO FOLLOW IN STEADY TRACING AND RHYTHM

    // Give back the point a distance of along down the path, in points, using the kept path
    static func pointAlong(_ path: Path, _ along: Double) -> (Double, Double) {
        let p: [Double] = JSCore.must("train.pointAlong", path.arg, along)
        return (p[0], p[1])
    }


    // STEADY TRACING

    // How many turns the tracing spiral has
    static let traceTurns: Double = JSCore.must("train.TRACE_TURNS")

    // How close a hit stays to the spiral on average, as a share of its radius
    static let traceLimit: Double = JSCore.must("train.TRACE_LIMIT")

    // Make the spiral centered in a w by h area, starting from the middle, and keep it in the JavaScript
    static func tracingPath(_ w: Double, _ h: Double) -> Path {
        let kept: (value: Path, ref: Int) = JSCore.mustKeep("train.tracingPath", w, h)
        var path = kept.value
        path.ref = kept.ref
        return path
    }

    // Judge a steady tracing try
    static func scoreTracing(_ samples: [Sample], _ strokeStarts: [Int], _ path: Path, _ recent: [[String: Double]] = []) -> Outcome {
        JSCore.must("train.scoreTracing", samples.forJS, strokeStarts, path.arg, recent)
    }


    // RHYTHM

    // How many beats the wave has
    static let rhythmBeats: Double = JSCore.must("train.RHYTHM_BEATS")

    // How many beats are counted in before the dot sets off
    static let countIn: Double = JSCore.must("train.COUNT_IN")

    // How many beats behind the dot a hit stays on average, and how close it stays to the wave
    static let rhythmLag: Double = JSCore.must("train.RHYTHM_LAG")
    static let rhythmNear: Double = JSCore.must("train.RHYTHM_NEAR")

    // Make the wave across a w by h area and keep it in the JavaScript
    // Beat k ends at a top or a bottom, at along equal to k times beatLength
    static func rhythmPath(_ w: Double, _ h: Double) -> Path {
        let kept: (value: Path, ref: Int) = JSCore.mustKeep("train.rhythmPath", w, h)
        var path = kept.value
        path.ref = kept.ref
        return path
    }

    // The beat length and pen start time sent to train.js
    private struct Timing: Encodable {
        var beatSec: Double
        var penOffset: Double
    }

    // Judge a rhythm try
    // penOffset is the seconds from the dot setting off to the pen's first sample, and is negative if the pen was down first
    static func scoreRhythm(_ samples: [Sample], _ strokeStarts: [Int], _ path: Path, _ timing: (beatSec: Double, penOffset: Double), _ recent: [[String: Double]] = []) -> Outcome {
        JSCore.must("train.scoreRhythm", samples.forJS, strokeStarts, path.arg, Timing(beatSec: timing.beatSec, penOffset: timing.penOffset), recent)
    }


    // HAND SKILLS WITH SHRINKING TARGETS

    // How many targets a try has
    static let targets: Int = JSCore.must("train.TARGETS")

    // How many seconds a target takes to shrink from its starting size to nothing
    static let shrinkSecs: Double = JSCore.must("train.SHRINK_SECS")

    // The share of targets a hit catches, and the share of all taps that land on a circle
    static let catchShare: Double = JSCore.must("train.CATCH_SHARE")
    static let tapPrecision: Double = JSCore.must("train.TAP_PRECISION")

    // Give back the target's radius secs after it appeared, or 0 once it is gone
    static func targetRadius(_ startSize: Double, _ secs: Double) -> Double {
        JSCore.must("train.targetRadius", startSize, secs)
    }

    // Judge a hand skills try, where results has one entry per target and extraTaps is the taps that missed every target
    static func scoreTargets(_ results: [TargetResult], _ extraTaps: Int) -> Outcome {
        JSCore.must("train.scoreTargets", results, extraTaps)
    }
}
