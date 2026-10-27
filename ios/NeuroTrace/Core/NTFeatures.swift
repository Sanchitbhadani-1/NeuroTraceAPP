// NTFEATURES.SWIFT TURNS A SPIRAL DRAWING INTO ITS MEASUREMENTS
// IT CALLS app/core/nt-features.js THROUGH JSCORE

import Foundation

// Runs the measuring steps in nt-features.js
enum NTFeatures {

    // The order the model reads the measures in
    static let spiralFeatureOrder: [String] = JSCore.must("features.SPIRAL_FEATURE_ORDER")

    // Run one nt-features.js function, and throw an NTError with the JavaScript's message if it fails
    private static func run<T: Decodable>(_ name: String, _ args: [any Encodable]) throws -> T {
        do {
            return try JSCore.call("features." + name, args: args)
        } catch let failure as JSCore.Failure where !failure.reason.isEmpty {
            throw NTError(failure.reason)
        }
    }

    // The drawing as featuresFromTrace reads it
    private struct TraceInput: Encodable {
        var task: String
        var samples: [JSPoint]
    }

    // Take a recorded drawing and give back every measure
    static func featuresFromTrace(_ trace: Trace, _ fs: Double = 100.0) throws -> [String: Double] {
        try run("featuresFromTrace", [TraceInput(task: trace.task, samples: trace.samples.forJS), fs])
    }

    // Clean the drawing, trim the still ends, resample to fs, normalize and low pass
    static func preprocessTrace(_ t: [Double], _ x: [Double], _ y: [Double], _ fs: Double = 100.0, _ cutoff: Double = 15.0, _ trim: Bool = true) throws -> ([Double], [Double], [Double]) {
        let out: [[Double]] = try run("preprocessTrace", [t, x, y, fs, cutoff, trim])
        return (out[0], out[1], out[2])
    }

    // Center the drawing on the middle and scale it to an average radius of 1
    static func normalize(_ x: [Double], _ y: [Double]) -> ([Double], [Double]) {
        let out: [[Double]] = JSCore.must("features.normalize", x, y)
        return (out[0], out[1])
    }

    // Give back how far each point is from the spiral fitted to the drawing
    static func spiralFitResidual(_ x: [Double], _ y: [Double], _ minTurns: Double = 1.0) throws -> [Double] {
        try run("spiralFitResidual", [x, y, minTurns])
    }
}
