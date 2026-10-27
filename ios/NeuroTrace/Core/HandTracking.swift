// HANDTRACKING.SWIFT CHECKS IF THIS DEVICE IS NEW ENOUGH FOR FINGER TAPPING
// IT TURNS OFF HAND TRACKING ON IPADS WITH A MODEL NUMBER OF IPAD7 OR LOWER

import Foundation

// Load the C library that has uname when building on Linux
#if canImport(Glibc)
import Glibc
#endif

// Reads the device model and decides if hand tracking can run
enum HandTracking {

    // The model number, like iPad7,11
    static var model: String {

        // In the Simulator, use the model it is acting as
        if let acting = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return acting }

        // Otherwise read the model from the system and turn it into text
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { bytes in String(decoding: bytes.prefix { b in b != 0 }, as: UTF8.self) }
    }

    // True for every model except iPads with a number below 8
    static func newEnough(_ model: String) -> Bool {

        // Anything that is not an iPad, or has no number after "iPad", is new enough
        guard model.hasPrefix("iPad"), let number = Int(model.dropFirst(4).prefix { c in c.isNumber }) else { return true }
        return number >= 8
    }

    // Whether this device is new enough
    static let newEnoughHere = newEnough(model)
}
