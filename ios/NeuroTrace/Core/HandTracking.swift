import Foundation
#if canImport(Glibc)
import Glibc
#endif

// Finger tapping uses Apple's hand tracking, which doesn't run well enough on iPads with the older A10 and
// A10X chips. Those are iPad (6th and 7th generation) and the 2017 iPad Pros, all named iPad7 in their model numbers
enum HandTracking {
    // The model number, like iPad7,11. The Simulator gives the model it's acting as
    static var model: String {
        if let acting = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return acting }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { bytes in String(decoding: bytes.prefix { b in b != 0 }, as: UTF8.self) }
    }

    // True unless it's one of those older iPads. Every iPhone that runs NeuroTrace is new enough
    static func newEnough(_ model: String) -> Bool {
        guard model.hasPrefix("iPad"), let number = Int(model.dropFirst(4).prefix { c in c.isNumber }) else { return true }
        return number >= 8
    }

    static let newEnoughHere = newEnough(model)
}
