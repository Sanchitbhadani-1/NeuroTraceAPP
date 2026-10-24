import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

private let order = ["f0", "f1"]

private func scoreArray(_ below: Int) -> [Double] {
    Array(repeating: 0, count: below) + Array(repeating: 1, count: 1000 - below)
}

private func block(n: Int = 40, mean: [Double] = [0, 0], sd: [Double] = [1, 1], score: [Double] = scoreArray(500)) -> Score.Bracket {
    Score.Bracket(n: n, mean: mean, sd: sd, features: ["f0": [0, 1, 2], "f1": [0, 1, 2]], score: score)
}

// A JSON file's bytes, built from plain Swift dictionaries and arrays
private func data(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }

// The same object with one field swapped out
private func with(_ object: [String: Any], _ key: String, _ value: Any) -> [String: Any] {
    var changed = object
    changed[key] = value
    return changed
}

final class ScoreTests: XCTestCase {
    func testScore() throws {
        let flatModel = Score.Model(version: 2, featureOrder: order, weights: [0, 0], bias: 0)
        let perTrial: [[String: Double]] = [["f0": 5, "f1": 5]]

        for (below, wantTier) in [(749, 0), (750, 1), (950, 2)] {
            let reference = Score.Reference(deviceMatched: true, trialsPerSession: 1, minBracketN: 1,
                brackets: ["all": block(score: scoreArray(below))])
            let r = Score.scoreSession(perTrial, flatModel, reference, nil)
            XCTAssertEqual(r.scorePct, Double(below) / 1000)
            XCTAssertEqual(r.tier, wantTier, "scorePct \(r.scorePct) should give tier \(wantTier)")
        }

        let refBrackets = Score.Reference(
            minBracketN: 12,
            brackets: [
                "all": block(n: 40),
                "60s": block(n: 5),
                "70s": block(n: 20),
            ]
        )
        XCTAssertEqual(Score.bracketFor(refBrackets, "80+").key, "all")
        XCTAssertEqual(Score.bracketFor(refBrackets, "60s").key, "all")
        XCTAssertEqual(Score.bracketFor(refBrackets, nil).key, "all")
        XCTAssertEqual(Score.bracketFor(refBrackets, Optional<String>.none).key, "all")
        XCTAssertEqual(Score.bracketFor(refBrackets, "70s").key, "70s")
        XCTAssertEqual(Score.bracketFor(refBrackets, "70s").block, refBrackets.brackets["70s"])

        do {
            let model = Score.Model(version: 2, featureOrder: order, weights: [1, 1], bias: 0)
            let reference = Score.Reference(deviceMatched: false, trialsPerSession: 1, minBracketN: 1,
                brackets: ["all": block()])
            let r = Score.scoreSession([["f0": 5, "f1": .nan]], model, reference, nil)
            XCTAssertEqual(r.features["f0"], 5)
            XCTAssertTrue(r.features["f1"]!.isNaN)
            XCTAssertTrue(r.measurePct["f0"] != nil)
            XCTAssertTrue(r.measurePct["f1"] == nil)
            XCTAssertEqual(r.topSignals, ["f0"])
        }

        do {
            let model = Score.Model(version: 2, featureOrder: order, weights: [1, 1], bias: 0)
            let reference = Score.Reference(deviceMatched: false, trialsPerSession: 1, minBracketN: 1,
                brackets: ["all": block(sd: [0, .nan])])
            let r = Score.scoreSession([["f0": 5, "f1": 5]], model, reference, nil)
            XCTAssertEqual(r.score, 0.5)
        }

        do {
            let avg = Score.averageFeatures([["f0": 1], ["f0": .nan], ["f0": 3]], ["f0"])
            XCTAssertEqual(avg["f0"], 2)
            let allNaN = Score.averageFeatures([["f0": .nan], ["f0": .nan]], ["f0"])
            XCTAssertTrue(allNaN["f0"]!.isNaN)
        }

        do {
            let model = Score.Model(version: 2, featureOrder: ["f0", "f1", "f2"], weights: [1, -1, 1], bias: 0)
            let reference = Score.Reference(deviceMatched: false, trialsPerSession: 1, minBracketN: 1,
                brackets: ["all": Score.Bracket(n: 10, mean: [0, 0, 0], sd: [1, 1, 1],
                    features: ["f0": [0], "f1": [0], "f2": [0]], score: scoreArray(500))])
            let r = Score.scoreSession([["f0": 2, "f1": 2, "f2": 1]], model, reference, nil)
            XCTAssertEqual(r.topSignals, ["f0", "f2", "f1"])
        }

        do {
            let goodModel: [String: Any] = ["version": 2, "featureOrder": ["f0", "f1"], "weights": [1, 1], "bias": 0]
            let goodRef: [String: Any] = ["version": 2, "featureOrder": ["f0", "f1"], "minBracketN": 1,
                "brackets": ["all": try JSONSerialization.jsonObject(with: JSONEncoder().encode(block()))]]
            XCTAssertNoThrow(try Score.checkScoringFiles(data(goodModel), data(goodRef), order))
            XCTAssertThrowsError(try Score.checkScoringFiles(data(with(goodModel, "featureOrder", ["f1", "f0"])), data(goodRef), order))
            XCTAssertThrowsError(try Score.checkScoringFiles(data(with(goodModel, "weights", [1])), data(goodRef), order))
            XCTAssertThrowsError(try Score.checkScoringFiles(data(with(goodModel, "version", 1)), data(goodRef), order))
            XCTAssertThrowsError(try Score.checkScoringFiles(data(goodModel), data(with(goodRef, "brackets", [String: Any]())), order))
            // A wrong type, a null or an odd version is reported with the field's name instead of crashing
            for (key, value, place) in [("bias", "zero", "at bias"), ("weights", [1, NSNull()], "at weights.1"), ("version", 2.5, "version is 2.5")] as [(String, Any, String)] {
                XCTAssertThrowsError(try Score.checkScoringFiles(data(with(goodModel, key, value)), data(goodRef), order)) { error in
                    XCTAssertTrue((error as? NTError)?.message.contains(place) == true, "\(error)")
                }
            }
            XCTAssertThrowsError(try Score.checkScoringFiles(Data("[1, 2]".utf8), data(goodRef), order)) { error in
                XCTAssertTrue((error as? NTError)?.message.contains("at the top level") == true, "\(error)")
            }
            XCTAssertThrowsError(try Score.checkScoringFiles(Data("{ not json".utf8), data(goodRef), order)) { error in
                XCTAssertTrue((error as? NTError)?.message.contains("couldn't be read as JSON") == true, "\(error)")
            }
        }

        do {
            let resources = repoRoot.appendingPathComponent("ios/NeuroTrace/Resources")
            let model = try Data(contentsOf: resources.appendingPathComponent("model.json"))
            let reference = try Data(contentsOf: resources.appendingPathComponent("reference.json"))
            XCTAssertNoThrow(try Score.checkScoringFiles(model, reference, NTFeatures.spiralFeatureOrder))
        }

        XCTAssertEqual(Score.fractionBelow(5, [1, 2, 3, 4, 5, 6]), 4.0 / 6)

        do {
            let validGroups = Set(Copy.groups.map { g in g.id })
            for k in NTFeatures.spiralFeatureOrder {
                XCTAssertTrue(Copy.measures[k] != nil, "Copy.measures is missing \"\(k)\"")
                XCTAssertTrue(validGroups.contains(Copy.measures[k]?.group ?? ""), "Copy.measures[\"\(k)\"].group is not a real group")
            }
        }

        do {
            let hi = Copy.measures["spiral_duration"]!.hi, lo = Copy.measures["spiral_duration"]!.lo
            XCTAssertEqual(Copy.measureSentence("spiral_duration", 0.5), "\(hi) 50% of the reference group")
            XCTAssertEqual(Copy.measureSentence("spiral_duration", 0.86), "\(hi) 86% of the reference group")
            XCTAssertEqual(Copy.measureSentence("spiral_duration", 0.23), "\(lo) 77% of the reference group")
        }

        print("SCORE OK")
    }

    // The model card has to show the model's real arithmetic, not a picture of it. Runs on the shipped
    // model.json and reference.json, so a retrain is tested too
    func testModelCard() throws {
        let resources = repoRoot.appendingPathComponent("ios/NeuroTrace/Resources")
        let model = try JSONDecoder().decode(Score.Model.self, from: Data(contentsOf: resources.appendingPathComponent("model.json")))
        let reference = try JSONDecoder().decode(Score.Reference.self, from: Data(contentsOf: resources.appendingPathComponent("reference.json")))
        let all = try XCTUnwrap(reference.brackets["all"])
        let offsets: [Double] = [1.5, -0.5, 2, 0.3, -1.2, 0.8, 2.5, -2, 1, 0.1, -0.7, 1.8]

        // A made-up person: each measure some number of healthy SDs from typical, times `scale`
        func person(_ scale: Double) -> [[String: Double]] {
            var f: [String: Double] = [:]
            for (i, k) in model.featureOrder.enumerated() {
                f[k] = all.mean[i] + scale * offsets[i % offsets.count] * all.sd[i]
            }
            return [f]
        }

        do {
            let r = Score.scoreSession(person(1), model, reference, nil)
            let c = try XCTUnwrap(r.contributions)
            XCTAssertEqual(c.count, model.featureOrder.count)
            XCTAssertEqual(model.bias + c.values.reduce(0, +), log(r.score / (1 - r.score)), accuracy: 1e-9)
            // The bias plus every bar adds up to exactly the number the score came from. If this holds,
            // the bars are the model, not a picture of it

            let bars = Score.contributionBars(r)
            XCTAssertEqual(bars.count, model.featureOrder.count)
            XCTAssertEqual(bars.map { b in abs(c[b.key]!) }, bars.map { b in abs(c[b.key]!) }.sorted(by: >))
            XCTAssertTrue(bars.allSatisfy { b in b.frac >= 0 && b.frac <= 1 })
            XCTAssertTrue(bars.allSatisfy { b in b.raises == (c[b.key]! >= 0) })
        }

        do {
            let r = Score.scoreSession(person(0.1), model, reference, nil)
            XCTAssertLessThan(Score.contributionBars(r)[0].frac, 0.5)
            // Barely unusual everywhere: the biggest bar stays short instead of stretching to full width
        }

        do {
            var f = person(1)[0]
            f[model.featureOrder[0]] = .nan
            let r = Score.scoreSession([f], model, reference, nil)
            XCTAssertNil(r.contributions?[model.featureOrder[0]])
            XCTAssertFalse(Score.contributionBars(r).contains { b in b.key == model.featureOrder[0] })
        }

        do {
            let r = Score.scoreSession(person(1), model, reference, nil)
            var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(r)) as? [String: Any])
            old["contributions"] = nil
            old["contributionScale"] = nil
            let decoded = try JSONDecoder().decode(Score.Result.self, from: JSONSerialization.data(withJSONObject: old))
            XCTAssertNil(decoded.contributions)
            XCTAssertEqual(Score.contributionBars(decoded), [])
            XCTAssertEqual(decoded.scorePct, r.scorePct, accuracy: 1e-12)
            // A check-in saved before contributions existed still loads; its card just shows no bars
        }

        XCTAssertTrue(Copy.modelDisclaimer.contains("7 times in 10"), Copy.modelDisclaimer)
        XCTAssertTrue(Copy.modelDisclaimer.contains("AUC 0.71"), Copy.modelDisclaimer)

        print("MODEL CARD OK")
    }
}
