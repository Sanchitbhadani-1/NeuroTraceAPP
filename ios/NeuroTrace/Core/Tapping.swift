// TAPPING.SWIFT COUNTS THE TAPS IN A FINGER TAPPING TEST
// IT CALLS app/core/tapping.js THROUGH JSCORE

import Foundation

// Reads the tap limit from tapping.js and measures a test
enum Tapping {

    // The fewest taps a test needs
    static let minTaps: Int = JSCore.must("tapping.MIN_TAPS")

    // What analyzeTaps sends to tapping.js
    private struct Input: Encodable {
        var samples: [TapSample]
    }

    // Measure the taps from the camera samples
    // In each sample, t is seconds since the first frame and gap is fingertip distance over hand size, or nil
    static func analyzeTaps(_ samples: [TapSample]) -> TapResult {
        JSCore.must("tapping.analyzeTaps", Input(samples: samples))
    }
}
