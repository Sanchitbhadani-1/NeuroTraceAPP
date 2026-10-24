import Foundation

// Is this drawing a real attempt at the spiral? Asked before a spiral is kept, so a scribble can't
// turn into a confident-looking result. The thresholds come from real drawings:
//
//                                                     mean deviation    how long it took
//   worst of the 112 training people (Parkinson's included)    0.149       4.1 s at fastest
//   a real spiral traced on the iPad simulator, Oct 19     0.04 to 0.07     11 to 13 s
//   15 scribbles on the iPad simulator, Oct 19 to 21       0.21 to 0.41     0.7 to 2.4 s
//
// Mean deviation is how far the line sits from the ideal spiral fitted to it, in units of the
// drawing's own size (NTFeatures.spiralFitResidual), so it means the same thing on any screen
enum SpiralCheck {
    static let maxMeanDeviation = 0.20
    static let minSeconds = 3.0

    // A spiral that fails is never scored, however many times it's drawn, so a scribble can't get a
    // result by being tried again. After this many redos the message changes to say they can take as
    // long as they need or stop for now. Real spirals pass easily, even very shaky ones (see the tests)
    static let hintAfter = 2

    enum Problem: Equatable {
        case offGuide   // the line doesn't follow a spiral
        case tooFast    // finished too quickly to have traced one
    }

    static func problem(_ features: [String: Double]) -> Problem? {
        if let m = features["spiral_mean_deviation"], m.isFinite, m > maxMeanDeviation { return .offGuide }
        if let s = features["spiral_duration"], s.isFinite, s < minSeconds { return .tooFast }
        return nil
        // Off-guide is checked first because a scribble is usually both, and "follow the gray line"
        // tells someone what to do differently. A missing or NaN measure can't be judged, so it
        // isn't held against the drawing
    }
}
