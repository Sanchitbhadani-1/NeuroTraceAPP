import Foundation

// The NeuroTrace feature pipeline. app/nt-features.js does the work, called through JSCore. It mirrors
// training/neurotrace/preprocess.py and features.py function for function, and the parity test checks
// it gives Python's numbers

enum NTFeatures {
    // The order the model reads the measures in
    static let spiralFeatureOrder: [String] = JSCore.must("features.SPIRAL_FEATURE_ORDER")

    // Runs one nt-features.js function. Its errors come back as NTError, with the JavaScript's message
    private static func run<T: Decodable>(_ name: String, _ args: [any Encodable]) throws -> T {
        do {
            return try JSCore.call("features." + name, args: args)
        } catch let failure as JSCore.Failure where !failure.reason.isEmpty {
            throw NTError(failure.reason)
        }
    }

    private struct TraceInput: Encodable {
        var task: String
        var samples: [JSPoint]
    }

    // The front door. Takes the trace the app records and gives back every measure
    static func featuresFromTrace(_ trace: Trace, _ fs: Double = 100.0) throws -> [String: Double] {
        try run("featuresFromTrace", [TraceInput(task: trace.task, samples: trace.samples.forJS), fs])
    }

    // clean, trim the still ends, resample to fs, normalize and low pass
    static func preprocessTrace(_ t: [Double], _ x: [Double], _ y: [Double], _ fs: Double = 100.0, _ cutoff: Double = 15.0, _ trim: Bool = true) throws -> ([Double], [Double], [Double]) {
        let out: [[Double]] = try run("preprocessTrace", [t, x, y, fs, cutoff, trim])
        return (out[0], out[1], out[2])
    }

    // centered on the middle and scaled to an average radius of 1
    static func normalize(_ x: [Double], _ y: [Double]) -> ([Double], [Double]) {
        let out: [[Double]] = JSCore.must("features.normalize", x, y)
        return (out[0], out[1])
    }

    // how far each point is from the spiral fitted to the drawing itself
    static func spiralFitResidual(_ x: [Double], _ y: [Double], _ minTurns: Double = 1.0) throws -> [Double] {
        try run("spiralFitResidual", [x, y, minTurns])
    }
}
