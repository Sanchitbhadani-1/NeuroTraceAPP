import Foundation

// Finger tapping. Aryan's app/tapping.js counts the taps, called through JSCore

enum Tapping {
    // Fewer taps than this and the numbers say little
    static let minTaps: Int = JSCore.must("tapping.MIN_TAPS")

    private struct Input: Encodable {
        var samples: [TapSample]
    }

    // samples. t is seconds since the first frame, gap is fingertip distance over hand size, or nil
    static func analyzeTaps(_ samples: [TapSample]) -> TapResult {
        JSCore.must("tapping.analyzeTaps", Input(samples: samples))
    }
}
