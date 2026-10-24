import Foundation

// Which hand the camera sees during finger tapping. Apple's hand tracking guesses "left" or "right" on each
// frame. One guess can be wrong, so this only answers when enough frames agree

enum HandCheck {
    // Frames with a guess needed before it says anything, during a test and while getting ready
    static let minFrames = 15
    static let minFramesLive = 10
    // Share of those frames that have to agree
    static let agree = 0.8

    // "left" or "right" when the guesses clearly agree, nil when there are too few or they're mixed.
    // Anything other than "left" or "right" (a frame with no hand) doesn't count either way
    static func seen(_ guesses: [String], minFrames: Int = minFrames) -> String? {
        let left = guesses.filter { g in g == "left" }.count, right = guesses.filter { g in g == "right" }.count
        let total = left + right
        guard total >= minFrames else { return nil }
        if Double(left) >= agree * Double(total) { return "left" }
        if Double(right) >= agree * Double(total) { return "right" }
        return nil
    }

    // The hand the camera saw, when it clearly wasn't the one picked. nil when it matched or couldn't tell
    static func otherHand(picked: String, guesses: [String], minFrames: Int = minFrames) -> String? {
        guard let hand = seen(guesses, minFrames: minFrames), hand != picked else { return nil }
        return hand
    }
}
