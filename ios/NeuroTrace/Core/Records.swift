import Foundation

// Create an error struct with localized error protocols (be able to give a message) and equatable protocol (be able to determine equality)
struct NTError: LocalizedError, Equatable {
    var message: String
    init(_ message: String) {
        self.message = message
    }

    // Make errorDescription = the message
    var errorDescription: String? {
        message
    }
}

// Create a setting called forExport that determines whether something is for export or not
extension CodingUserInfoKey {
    static let forExport = CodingUserInfoKey(rawValue: "neurotrace.forExport")!
}

// Create the basic variables used in a sample, codable and equatable are the protocols for encoding and decoding, and checking equality, respectively
struct Sample: Codable, Equatable {
    var t: Double
    var x: Double
    var y: Double
    var pressure: Double = 0
    var tiltX: Double = 0
    var tiltY: Double = 0

    // Explicitly create the CodingKeys enum
    enum CodingKeys: String, CodingKey {
        case t
        case x
        case y
        case pressure
        case tiltX
        case tiltY
    }
}

// Rewrite the decoding process rather than using Swift's built-in decoder. Give instructions on how to decode a JSON format sample
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

// Create the Trace type, which holds an array of samples
struct Trace: Codable, Equatable {
    var task: String
    var hand: String?
    var inputType: String?
    var deviceLabel: String
    var samples: [Sample]
}

// Create a copy of a drawing for replays but it takes lest storage.
struct ReplayPath: Codable, Equatable {
    var t: [Float]
    var x: [Float]
    var y: [Float]
    
    var starts: [Int] // The index where each stroke starts (where the pen was put back down)

    // Rewrite the encoding process. When exporting, round t, x and y to 2 decimals so the file is smaller
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        
        if encoder.userInfo[.forExport] as? Bool == true { // Check the forExport setting (counts as false if it was never set)
            // A function that rounds every number in a list to 2 decimals, the same way JavaScript rounds
            let round = { (v: [Float]) in v.map { n in jsRound(Double(n) * 100) / 100 } }
            try c.encode(round(t), forKey: .t)
            try c.encode(round(x), forKey: .x)
            try c.encode(round(y), forKey: .y)
        } else {
            try c.encode(t, forKey: .t)
            try c.encode(x, forKey: .x)
            try c.encode(y, forKey: .y)
        }
        try c.encode(starts, forKey: .starts)
    }
}

// A lighter copy of a drawing for replays, about 60 points a second, keeping where each stroke starts and ends
let replayHz = 60.0
func replayPath(_ samples: [Sample], _ strokeStarts: [Int] = [0]) -> ReplayPath {
    let starts = Set(strokeStarts)
    var keep: [Int] = []
    var last = -Double.infinity
    for (i, s) in samples.enumerated() {
        let edge = starts.contains(i) || starts.contains(i + 1) || i == samples.count - 1
        if edge || s.t - last >= 1 / replayHz {
            keep.append(i)
            last = s.t
        }
    }
    let pick = { (k: KeyPath<Sample, Double>) in keep.map { i in Float(samples[i][keyPath: k]) } }
    return ReplayPath(t: pick(\.t), x: pick(\.x), y: pick(\.y), starts: keep.enumerated().flatMap { (j, i) in starts.contains(i) ? [j] : [] })
}

// Create one of the three spirals in a check-in. Samples and strokeStarts are optional because only the 3 newest check-ins keep them
struct AssessmentTrial: Codable, Equatable {
    var samples: [Sample]?
    var strokeStarts: [Int]?
    // The 12 measures for this spiral, by name
    var features: [String: Double]
    var path: ReplayPath?
}

// Create one whole check-in: who drew it, how, the three spirals, and the result
struct AssessmentRecord: Codable, Equatable {
    // Store gives each check-in an id when it's saved, so it's nil before that
    var id: Int?
    // When it happened, in milliseconds since 1970 (like JavaScript's Date.now())
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
    // The scoring result, defined in Score.swift
    var result: Score.Result?
}
