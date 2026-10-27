// SCORE.SWIFT TURNS A CHECK IN'S MEASUREMENTS INTO A RESULT BY CALLING SCORE.JS
// IT ALSO CHECKS THE SCORING FILES AND WORKS OUT THE BARS ON THE MODEL CARD

import Foundation

// Scores a check in against the reference group
enum Score {

    // The model read from model.json
    struct Model: Codable, Equatable {
        var version: Int
        var featureOrder: [String]
        var weights: [Double]
        var bias: Double
    }

    // One reference group, with its size, the average and spread of each measure, and every value
    struct Bracket: Codable, Equatable {
        var n: Int
        var mean: [Double]
        var sd: [Double]
        var features: [String: [Double]]
        var score: [Double]
    }

    // The reference groups read from reference.json
    struct Reference: Codable, Equatable {
        var version: Int?
        var featureOrder: [String]?
        var deviceMatched: Bool?
        var trialsPerSession: Int?
        var minBracketN: Int?
        var brackets: [String: Bracket]
    }

    // The result of one check in
    struct Result: Codable, Equatable {
        var features: [String: Double]
        var bracketKey: String
        var referenceN: Int
        var deviceMatched: Bool
        var trialsPerSession: Int?
        var tier: Int
        var measurePct: [String: Double]
        var topSignals: [String]
        var score: Double
        var scorePct: Double

        // How far each measure moved the score, the model's weight times how far the measure was from typical
        // It is nil for check ins saved without it
        var contributions: [String: Double]? = nil

        // The value a full length bar stands for, the biggest weight times two
        var contributionScale: Double? = nil
    }

    // One bar on the model card
    struct Bar: Equatable {
        var key: String

        // The bar's length, from 0 to 1
        var frac: Double

        // True if this measure pushed the result up
        var raises: Bool
    }

    // Make a bar for every measure the model used, biggest influence first
    static func contributionBars(_ r: Result) -> [Bar] {

        // Keep the measures that have a percentile and a real number
        let used = (r.contributions ?? [:]).filter { pair in r.measurePct[pair.key] != nil && pair.value.isFinite }

        // Use the larger of the biggest value and contributionScale as the full bar length
        let biggest = used.values.map { v in abs(v) }.max() ?? 0
        let scale = max(biggest, r.contributionScale ?? 0)

        // Sort by size, then by name, and turn each one into a bar
        return used
            .sorted { a, b in abs(a.value) != abs(b.value) ? abs(a.value) > abs(b.value) : a.key < b.key }
            .map { pair in Bar(key: pair.key, frac: scale > 0 ? abs(pair.value) / scale : 0, raises: pair.value >= 0) }
    }

    // The cut points between the result tiers, read from score.js
    static let tierCuts: [Double] = JSCore.must("score.TIER_CUTS")

    // Give back the top signals that pushed the result up
    // Check ins with no contributions give back all their top signals
    static func pushedUp(_ r: Result) -> [String] {
        guard let contributions = r.contributions else { return r.topSignals }
        return r.topSignals.filter { k in (contributions[k] ?? 0) > 0 }
    }


    // CHECKING THE SCORING FILES

    // model.json read with every field optional, and version read as a Double
    private struct ModelFile: Decodable {
        var version: Double?
        var featureOrder: [String]?
        var weights: [Double]?
        var bias: Double?
    }

    // One reference group read with every field optional
    private struct BracketFile: Decodable {
        var mean: [Double]?
        var sd: [Double]?
        var features: [String: [Double]]?
        var score: [Double]?
    }

    // reference.json read with every field optional, and version read as a Double
    private struct ReferenceFile: Decodable {
        var version: Double?
        var featureOrder: [String]?
        var brackets: [String: BracketFile]?
    }

    // Check model.json and reference.json, and throw an NTError that says what is wrong
    // Swift reads the files first, then score.js checks what they say
    static func checkScoringFiles(_ modelData: Data, _ referenceData: Data, _ featureOrder: [String]) throws {

        // The sentence added to the end of every message
        let reExport = "Re-export with training/scripts/export_model.py."

        // Read both files into the optional types to check each value's type
        _ = try readScoringFile(ModelFile.self, modelData, "model.json", reExport)
        _ = try readScoringFile(ReferenceFile.self, referenceData, "reference.json", reExport)

        // Read both files as plain JSON to pass to score.js
        let model = try readScoringFile(JSONValue.self, modelData, "model.json", reExport)
        let reference = try readScoringFile(JSONValue.self, referenceData, "reference.json", reExport)

        // Ask score.js to check them, and turn its message into an NTError
        do {
            let _: JSONValue? = try JSCore.call("score.checkScoringFiles", model, reference, featureOrder)
        } catch let failure as JSCore.Failure where !failure.reason.isEmpty {
            throw NTError(failure.reason)
        }
    }

    // Read one scoring file, and throw an NTError that names the field when a value is wrong
    private static func readScoringFile<T: Decodable>(_ type: T.Type, _ data: Data, _ name: String, _ reExport: String) throws -> T {

        // A wrong type, a null or a bad value inside the file names the field
        // Anything else says the file couldn't be read as JSON
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            throw NTError("\(name) has a bad value at \(place(context)). \(reExport)")
        } catch let DecodingError.dataCorrupted(context) where !context.codingPath.isEmpty {
            throw NTError("\(name) has a bad value at \(place(context)). \(reExport)")
        } catch {
            throw NTError("\(name) couldn't be read as JSON. \(reExport)")
        }
    }

    // Give back where in a scoring file the problem is, like weights.1
    private static func place(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map { key in key.intValue.map { i in String(i) } ?? key.stringValue }.joined(separator: ".")
        return path.isEmpty ? "the top level" : path
    }


    // SCORING

    // The reference group bracketFor sends back, with its key
    private struct Placed: Decodable {
        var key: String
        var block: Bracket
    }

    // Give back the reference group to compare with, or everyone when that group is too small
    static func bracketFor(_ reference: Reference, _ bracketKey: String?) -> (key: String, block: Bracket) {
        let placed: Placed = JSCore.must("score.bracketFor", reference, bracketKey)
        return (key: placed.key, block: placed.block)
    }

    // Average each measure over the drawings in a check in
    static func averageFeatures(_ perTrial: [[String: Double]], _ featureOrder: [String]) -> [String: Double] {
        JSCore.must("score.averageFeatures", perTrial, featureOrder)
    }

    // Give back the share of values below v
    static func fractionBelow(_ v: Double, _ values: [Double]) -> Double {
        JSCore.must("score.fractionBelow", v, values)
    }

    // Score a check in against the reference group with score.js, then add the model card's numbers
    static func scoreSession(_ perTrial: [[String: Double]], _ model: Model, _ reference: Reference, _ bracketKey: String?) -> Result {

        // Ask score.js for the result
        var result: Result = JSCore.must("score.scoreSession", perTrial, model, reference, bracketKey)

        // For each measure, multiply the model's weight by how many SDs the measure is from the group's average
        if let block = reference.brackets[result.bracketKey] {
            var contributions: [String: Double] = [:]
            for (i, k) in model.featureOrder.enumerated() {
                guard let f = result.features[k], f.isFinite else { continue }
                let sd = block.sd[i]
                contributions[k] = model.weights[i] * (sd > 0 && sd.isFinite ? (f - block.mean[i]) / sd : 0)
            }
            result.contributions = contributions
        }

        // Set the full bar length to two times the biggest weight
        result.contributionScale = 2 * (model.weights.map { w in abs(w) }.max() ?? 0)
        return result
    }
}
