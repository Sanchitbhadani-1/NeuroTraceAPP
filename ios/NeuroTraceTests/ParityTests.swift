// Parity test: every trace in the fixture must give the same features in
// JavaScript as it does in Python.
//
//   python parity/make_reference.py <uci_root> parity/reference.json    (in training/)
//   node app/tools/parity.mjs training/parity/reference.json
//
// Tolerance is RELATIVE, because the features span 1e-6 (band power) to 1e2
// (duration). 1e-9 is roughly where float64 ordering differences land; a real
// port bug shows up orders of magnitude above it.

import Foundation
import XCTest
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

private struct ParityCase: Decodable {
    var name: String
    var task: String
    var samples: [Sample]
    var features: [String: Double]
}

private struct ParityFile: Decodable {
    var fs: Double
    var cases: [ParityCase]
}

let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

final class ParityTests: XCTestCase {
    func testParity() throws {
        let spiralFeatureOrder = NTFeatures.spiralFeatureOrder

        let tol = 1e-9
        let path = ProcessInfo.processInfo.environment["PARITY_REFERENCE"] ?? repoRoot.appendingPathComponent("training/parity/reference.json").path
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("No parity fixture at \(path). Make one with training/parity/make_reference.py.")
        }
        let ref = try JSONDecoder().decode(ParityFile.self, from: Data(contentsOf: URL(fileURLWithPath: path)))

        var worst = Dictionary(uniqueKeysWithValues: spiralFeatureOrder.map { k in (k, (rel: 0.0, case: "-")) })
        var failed = 0, ran = 0

        for c in ref.cases {
            let got: [String: Double]
            do {
                got = try NTFeatures.featuresFromTrace(Trace(task: c.task, hand: nil, inputType: nil, deviceLabel: "", samples: c.samples), ref.fs)
            } catch {
                print("FAIL \(c.name): Swift threw \"\(error.localizedDescription)\" but Python produced features")
                failed += 1
                continue
            }
            ran += 1

            for k in spiralFeatureOrder {
                let a = got[k] ?? .nan, b = c.features[k] ?? .nan
                if a.isNaN && b.isNaN { continue }
                let rel = abs(a - b) / max(1e-12, abs(b))
                let w = worst[k]!
                if rel > w.rel { worst[k] = (rel: rel, case: c.name) }
                if !(rel <= tol) {
                    print("FAIL \(c.name) \(k): swift=\(a) py=\(b) rel=\(String(format: "%.2e", rel))")
                    failed += 1
                }
            }
        }

        print("\n\(ran)/\(ref.cases.count) traces ran. Worst relative difference per feature:\n")
        for k in spiralFeatureOrder {
            let w = worst[k]!
            let rel = String(format: "%.2e", w.rel)
            print("  \(k.padding(toLength: 28, withPad: " ", startingAt: 0)) \(String(repeating: " ", count: max(0, 9 - rel.count)))\(rel)   \(w.case)")
        }
        print(failed != 0 ? "\n\(failed) MISMATCHES" : "\nPARITY OK - all \(ran) traces, all \(spiralFeatureOrder.count) features within \(tol)")
        XCTAssertEqual(failed, 0)
    }
}
