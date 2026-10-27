// SPIRALCHECK.SWIFT CHECKS IF A DRAWING IS A REAL TRY AT THE SPIRAL BEFORE IT IS KEPT
// IT LOOKS AT HOW FAR THE LINE IS FROM A SPIRAL AND HOW LONG THE DRAWING TOOK

import Foundation

// Finds the problem with a drawing, if there is one
enum SpiralCheck {

    // The most the line can be from the fitted spiral on average, in units of the drawing's size
    static let maxMeanDeviation = 0.20

    // The fewest seconds a drawing can take
    static let minSeconds = 3.0

    // How many redos happen before the message changes
    static let hintAfter = 2

    // The two problems a drawing can have
    enum Problem: Equatable {

        // The line does not follow a spiral
        case offGuide

        // The drawing was finished too quickly
        case tooFast
    }

    // Give back the drawing's problem, or nil if it passes
    // Off guide is checked first, and a missing or NaN measure counts as a pass
    static func problem(_ features: [String: Double]) -> Problem? {
        if let m = features["spiral_mean_deviation"], m.isFinite, m > maxMeanDeviation { return .offGuide }
        if let s = features["spiral_duration"], s.isFinite, s < minSeconds { return .tooFast }
        return nil
    }
}
