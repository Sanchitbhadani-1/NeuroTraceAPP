// RECORDS.SWIFT HOLDS THE TYPES THE APP SAVES, LIKE DRAWINGS, CHECK INS, DOSES AND PRACTICE TRIES
// IT ALSO SETS HOW SOME OF THEM ARE WRITTEN AS JSON AND MAKES THE LIGHTER REPLAY COPY OF A DRAWING

import Foundation

// An error that holds a message
struct NTError: LocalizedError, Equatable {
    var message: String
    init(_ message: String) {
        self.message = message
    }

    // Give back the message as the error's description
    var errorDescription: String? {
        message
    }
}

// A setting the encoder can carry that says the JSON is for export
extension CodingUserInfoKey {
    static let forExport = CodingUserInfoKey(rawValue: "neurotrace.forExport")!
}

// One point of a drawing, with its time, position, pressure and tilt
struct Sample: Codable, Equatable {
    var t: Double
    var x: Double
    var y: Double
    var pressure: Double = 0
    var tiltX: Double = 0
    var tiltY: Double = 0

    // The JSON keys for each field
    enum CodingKeys: String, CodingKey {
        case t
        case x
        case y
        case pressure
        case tiltX
        case tiltY
    }
}

// Read a sample from JSON, using 0 for a missing pressure or tilt
extension Sample {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Double.self, forKey: .t)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        pressure = try c.decodeIfPresent(Double.self, forKey: .pressure) ?? 0
        tiltX = try c.decodeIfPresent(Double.self, forKey: .tiltX) ?? 0
        tiltY = try c.decodeIfPresent(Double.self, forKey: .tiltY) ?? 0
    }
}

// One drawing, with the task, hand, input type, device and its samples
struct Trace: Codable, Equatable {
    var task: String
    var hand: String?
    var inputType: String?
    var deviceLabel: String
    var samples: [Sample]
}

// A smaller copy of a drawing for replays, with times and positions stored as Floats
struct ReplayPath: Codable, Equatable {
    var t: [Float]
    var x: [Float]
    var y: [Float]

    // The index where each stroke starts
    var starts: [Int]

    // Write the copy as JSON, rounding t, x and y to 2 decimals when it is for export
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        // Check the forExport setting, which counts as false when it is not set
        if encoder.userInfo[.forExport] as? Bool == true {

            // Round every number in a list to 2 decimals the same way JavaScript rounds
            let round = { (v: [Float]) in v.map { n in jsRound(Double(n) * 100) / 100 } }
            try c.encode(round(t), forKey: .t)
            try c.encode(round(x), forKey: .x)
            try c.encode(round(y), forKey: .y)
        } else {

            // Otherwise write the numbers as they are
            try c.encode(t, forKey: .t)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
        }
        try c.encode(starts, forKey: .starts)
    }
}

// How many points a second the replay copy keeps
let replayHz = 60.0

// Make the replay copy of a drawing, keeping about 60 points a second and every point where a stroke starts or ends
func replayPath(_ samples: [Sample], _ strokeStarts: [Int] = [0]) -> ReplayPath {
    let starts = Set(strokeStarts)

    // Keep a point if it starts or ends a stroke, or if enough time has passed since the last kept point
    var keep: [Int] = []
    var last = -Double.infinity
    for (i, s) in samples.enumerated() {
        let edge = starts.contains(i) || starts.contains(i + 1) || i == samples.count - 1
        if edge || s.t - last >= 1 / replayHz {
            keep.append(i)
            last = s.t
        }
    }

    // Copy the kept times and positions, and find where each stroke starts in the kept list
    let pick = { (k: KeyPath<Sample, Double>) in keep.map { i in Float(samples[i][keyPath: k]) } }
    return ReplayPath(t: pick(\.t), x: pick(\.x), y: pick(\.y), starts: keep.enumerated().flatMap { (j, i) in starts.contains(i) ? [j] : [] })
}

// One of the three spirals in a check in
// samples and strokeStarts are nil for check ins older than the 3 newest
struct AssessmentTrial: Codable, Equatable {
    var samples: [Sample]?
    var strokeStarts: [Int]?

    // The 12 measures for this spiral, by name
    var features: [String: Double]
    var path: ReplayPath?
}

// One whole check in, with who drew it, how, the three spirals, and the result
struct AssessmentRecord: Codable, Equatable {

    // The id Store gives it when it is saved, or nil before that
    var id: Int?

    // When it happened, in milliseconds since 1970
    var ts: Int
    var task: String
    var hand: String
    var ageChoice: String?
    var bracketChoice: String?
    var inputType: String?
    var deviceLabel: String
    var trials: [AssessmentTrial]?

    // The 12 measures averaged over the three spirals
    var features: [String: Double]?

    // The scoring result, from Score.swift
    var result: Score.Result?
}

// One medication dose the person logged
struct Dose: Codable, Equatable {

    // The id Store gives it when it is saved, or nil before that
    var id: Int? = nil

    // When the dose was taken, in milliseconds since 1970
    var ts: Int
}

// One point of a collection mode drawing, with only the time, position and pressure
struct CollectedSample: Codable, Equatable {
    var t: Double
    var x: Double
    var y: Double
    var pressure: Double
}

// One of the three spirals a participant draws in collection mode
struct CollectedTrial: Codable, Equatable {
    var trial: Int
    var task: String
    var samples: [CollectedSample]
}

// One collection mode session, with the participant's details and their three spirals
struct CollectedSession: Codable, Equatable {
    var id: Int?

    // The file format's version number
    var formatVersion: Int

    // A random 6 character participant id
    var subjectId: String

    // Which visit this is for the participant, starting at 1
    var session: Int
    var collectedAt: String
    var deviceLabel: String
    var inputType: String?
    var hand: String
    var age: Int?
    var diagnosis: String
    var medicationHoursAgo: Double?
    var consent: Bool
    var trials: [CollectedTrial]

    // Whether this session has been exported off the iPad yet
    var exported: Bool

    // Write the session as JSON, leaving out id and exported when it is for export
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let forExport = encoder.userInfo[.forExport] as? Bool == true
        if !forExport { try c.encode(id, forKey: .id) }
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(subjectId, forKey: .subjectId)
        try c.encode(session, forKey: .session)
        try c.encode(collectedAt, forKey: .collectedAt)
        try c.encode(deviceLabel, forKey: .deviceLabel)

        // Write every field, with null for a missing optional like inputType or age
        try c.encode(inputType, forKey: .inputType)
        try c.encode(hand, forKey: .hand)
        try c.encode(age, forKey: .age)
        try c.encode(diagnosis, forKey: .diagnosis)
        try c.encode(medicationHoursAgo, forKey: .medicationHoursAgo)
        try c.encode(consent, forKey: .consent)
        try c.encode(trials, forKey: .trials)
        if !forExport { try c.encode(exported, forKey: .exported) }
    }
}

// One practice exercise try and how it went
struct TrainingTry: Codable, Equatable {
    var id: Int?
    var ts: Int

    // Which exercise, "big-writing", "steady-tracing", "rhythm" or "hand-skills"
    var exercise: String
    var level: Int

    // The level's setting, which is the target height, guide strength, beats per minute or circle size
    var target: Double

    // Whether the try was long enough to judge
    var counted: Bool

    // True when it reached the target without being slower or shakier than recent tries
    var hit: Bool
    var reachedTarget: Bool
    var slower: Bool
    var shakier: Bool
    var measures: [String: Double]

    // How this try compared with recent tries for pace and smoothness, from Train.swift
    var vs: Train.Vs
    var inputType: String?

    // The replay copy of the drawing, or nil for hand skills
    var path: ReplayPath?

    // Sizes and positions on screen during the try, like the pad's width and height and where the target line was
    var geometry: [String: Double]?

    // For hand skills, whether each circle was caught and how fast, from Train.swift
    var results: [Train.TargetResult]?

    // Write the try as JSON in the same shape as the web app
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(ts, forKey: .ts)
        try c.encode(exercise, forKey: .exercise)
        try c.encode(level, forKey: .level)
        try c.encode(target, forKey: .target)
        try c.encode(counted, forKey: .counted)
        try c.encode(hit, forKey: .hit)
        try c.encode(reachedTarget, forKey: .reachedTarget)
        try c.encode(slower, forKey: .slower)
        try c.encode(shakier, forKey: .shakier)
        try c.encode(measures, forKey: .measures)
        try c.encode(vs, forKey: .vs)
        try c.encode(inputType, forKey: .inputType)

        // Leave out path, geometry and results when they are nil
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(geometry, forKey: .geometry)
        try c.encodeIfPresent(results, forKey: .results)
    }
}
