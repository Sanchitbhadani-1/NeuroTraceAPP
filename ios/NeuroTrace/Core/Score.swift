import Foundation

enum Score {

    struct Model: Codable, Equatable {
        var version: Int
        var featureOrder: [String]
        var weights: [Double]
        var bias: Double
    }

    struct Bracket: Codable, Equatable {
        var n: Int
        var mean: [Double]
        var sd: [Double]
        var features: [String: [Double]]
        var score: [Double]
    }

    struct Reference: Codable, Equatable {
        var version: Int?
        var featureOrder: [String]?
        var deviceMatched: Bool?
        var trialsPerSession: Int?
        var minBracketN: Int?
        var brackets: [String: Bracket]
    }

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
        // How far each measure moved the score: the model's weight times how unusual the measure was.
        // Optional so check-ins saved before this field existed still load.
        var contributions: [String: Double]? = nil
        // What a full-length bar stands for: the strongest measure sitting two healthy SDs from typical.
        // A fixed yardstick, so a measure that barely mattered gets a short bar instead of being
        // stretched to fill the card just because it was the biggest of a few small ones
        var contributionScale: Double? = nil
    }

    // One bar on the model card
    struct Bar: Equatable {
        var key: String
        var frac: Double    // the bar's length, 0 to 1
        var raises: Bool    // true if this measure pushed the combined result up
    }

    // The model card's bars: every measure the model used, biggest influence first
    static func contributionBars(_ r: Result) -> [Bar] {
        let used = (r.contributions ?? [:]).filter { pair in r.measurePct[pair.key] != nil && pair.value.isFinite }
        let biggest = used.values.map { v in abs(v) }.max() ?? 0
        let scale = max(biggest, r.contributionScale ?? 0)
        return used
            .sorted { a, b in abs(a.value) != abs(b.value) ? abs(a.value) > abs(b.value) : a.key < b.key }
            .map { pair in Bar(key: pair.key, frac: scale > 0 ? abs(pair.value) / scale : 0, raises: pair.value >= 0) }
    }

    static let tierCuts: [Double] = JSCore.must("score.TIER_CUTS")

    // The top signals that actually pushed the combined result up. On a very typical drawing every measure
    // pulls it down, and then none of them stood out. Check-ins saved before contributions existed keep
    // all their top signals
    static func pushedUp(_ r: Result) -> [String] {
        guard let contributions = r.contributions else { return r.topSignals }
        return r.topSignals.filter { k in (contributions[k] ?? 0) > 0 }
    }

    // What model.json and reference.json get read as for checking. Every field is optional, so a missing
    // one produces a clear message instead of a decoding error. version is read as a Double so a
    // version like 2.5 gets its own message too
    private struct ModelFile: Decodable {
        var version: Double?
        var featureOrder: [String]?
        var weights: [Double]?
        var bias: Double?
    }

    private struct BracketFile: Decodable {
        var mean: [Double]?
        var sd: [Double]?
        var features: [String: [Double]]?
        var score: [Double]?
    }

    private struct ReferenceFile: Decodable {
        var version: Double?
        var featureOrder: [String]?
        var brackets: [String: BracketFile]?
    }

    // Check model.json and reference.json before anything gets scored, so a bad export stops with a
    // message saying what's wrong instead of quietly producing wrong numbers. Swift reads the files first,
    // so a wrong type or a null gets named. Then Aryan's score.js checks what they say
    static func checkScoringFiles(_ modelData: Data, _ referenceData: Data, _ featureOrder: [String]) throws {
        let reExport = "Re-export with training/scripts/export_model.py."
        _ = try readScoringFile(ModelFile.self, modelData, "model.json", reExport)
        _ = try readScoringFile(ReferenceFile.self, referenceData, "reference.json", reExport)
        let model = try readScoringFile(JSONValue.self, modelData, "model.json", reExport)
        let reference = try readScoringFile(JSONValue.self, referenceData, "reference.json", reExport)
        do {
            let _: JSONValue? = try JSCore.call("score.checkScoringFiles", model, reference, featureOrder)
        } catch let failure as JSCore.Failure where !failure.reason.isEmpty {
            throw NTError(failure.reason)
        }
    }

    // Decode one scoring file. A wrong type, a null or a number that doesn't fit becomes a message
    // that names the field
    private static func readScoringFile<T: Decodable>(_ type: T.Type, _ data: Data, _ name: String, _ reExport: String) throws -> T {
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

    // Where in a scoring file the problem is, like weights.1
    private static func place(_ context: DecodingError.Context) -> String {
        let path = context.codingPath.map { key in key.intValue.map { i in String(i) } ?? key.stringValue }.joined(separator: ".")
        return path.isEmpty ? "the top level" : path
    }

    private struct Placed: Decodable {
        var key: String
        var block: Bracket
    }

    // The reference group to compare with, or everyone when that group is too small
    static func bracketFor(_ reference: Reference, _ bracketKey: String?) -> (key: String, block: Bracket) {
        let placed: Placed = JSCore.must("score.bracketFor", reference, bracketKey)
        return (key: placed.key, block: placed.block)
    }

    static func averageFeatures(_ perTrial: [[String: Double]], _ featureOrder: [String]) -> [String: Double] {
        JSCore.must("score.averageFeatures", perTrial, featureOrder)
    }

    static func fractionBelow(_ v: Double, _ values: [Double]) -> Double {
        JSCore.must("score.fractionBelow", v, values)
    }

    // Aryan's score.js places the check-in against the reference group. The model card's numbers
    // only exist in the iPad app, so they're added here. Each measure's weight times how unusual it was,
    // the same numbers score.js ranks the top signals by
    static func scoreSession(_ perTrial: [[String: Double]], _ model: Model, _ reference: Reference, _ bracketKey: String?) -> Result {
        var result: Result = JSCore.must("score.scoreSession", perTrial, model, reference, bracketKey)
        if let block = reference.brackets[result.bracketKey] {
            var contributions: [String: Double] = [:]
            for (i, k) in model.featureOrder.enumerated() {
                guard let f = result.features[k], f.isFinite else { continue }
                let sd = block.sd[i]
                contributions[k] = model.weights[i] * (sd > 0 && sd.isFinite ? (f - block.mean[i]) / sd : 0)
            }
            result.contributions = contributions
        }
        result.contributionScale = 2 * (model.weights.map { w in abs(w) }.max() ?? 0)
        return result
    }
}
