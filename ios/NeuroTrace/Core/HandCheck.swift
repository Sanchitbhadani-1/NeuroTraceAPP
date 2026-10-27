// HANDCHECK.SWIFT WORKS OUT WHICH HAND THE CAMERA SEES DURING FINGER TAPPING
// IT ONLY GIVES AN ANSWER WHEN ENOUGH FRAMES AGREE ON LEFT OR RIGHT

import Foundation

// Counts the left and right guesses from each camera frame and picks a hand
enum HandCheck {

    // How many frames with a guess are needed before it gives an answer, during a test and while getting ready
    static let minFrames = 15
    static let minFramesLive = 10

    // The share of those frames that have to agree
    static let agree = 0.8

    // Give back "left" or "right" when the guesses agree, or nil when there are too few or they are mixed
    // Guesses other than "left" or "right" are not counted
    static func seen(_ guesses: [String], minFrames: Int = minFrames) -> String? {

        // Count the left and right guesses
        let left = guesses.filter { g in g == "left" }.count, right = guesses.filter { g in g == "right" }.count
        let total = left + right

        // Give back nil if there are too few guesses
        guard total >= minFrames else { return nil }

        // Give back the hand that has enough of the guesses, or nil if neither does
        if Double(left) >= agree * Double(total) { return "left" }
        if Double(right) >= agree * Double(total) { return "right" }
        return nil
    }

    // Give back the hand the camera saw when it is not the one picked
    // Give back nil when it matches or when no hand is clear
    static func otherHand(picked: String, guesses: [String], minFrames: Int = minFrames) -> String? {
        guard let hand = seen(guesses, minFrames: minFrames), hand != picked else { return nil }
        return hand
    }
}
