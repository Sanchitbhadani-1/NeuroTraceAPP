// HOMESCANRULES.SWIFT CHECKS THE IDEAS FROM A HOME SAFETY SCAN
// IT CALLS app/core/homescan.js THROUGH JSCORE

import Foundation

// Reads the limits from homescan.js and cleans up the ideas
enum HomeScanRules {

    // The most ideas a scan can give, and the priorities an idea can have
    static let maxIdeas: Int = JSCore.must("homescan.MAX_IDEAS")
    static let priorities: [String] = JSCore.must("homescan.PRIORITIES")

    // The longest each piece of text can be, as homescan.js sends it
    private struct Limits: Decodable {
        var title: Int
        var why: Int
        var place: Int
        var room: Int

        // Read "where" from the JavaScript into place
        enum CodingKeys: String, CodingKey {
            case title, why, room
            case place = "where"
        }
    }

    // The longest each piece of text can be, read once from homescan.js
    static let limits: (title: Int, why: Int, place: Int, room: Int) = {
        let l: Limits = JSCore.must("homescan.LIMITS")
        return (title: l.title, why: l.why, place: l.place, room: l.room)
    }()

    // True when the text has any of the banned words in homescan.js
    static func isBanned(_ text: String) -> Bool {
        JSCore.must("helpers.isBanned", text)
    }

    // What cleanIdeas sends to homescan.js
    private struct CleanInput: Encodable {
        var raw: JSONValue?
        var max: Int
    }

    // Clean up the ideas from Gemini into at most limit ideas
    // raw is either the reply as text or a reply that is already read into values
    static func cleanIdeas(raw: Any?, max limit: Int = maxIdeas) -> HomeScanResult {

        // Turn text into a JSON string, and anything else into a JSON value
        let value: JSONValue? = raw.flatMap { r in (r as? String).map { text in .string(text) } ?? JSONValue.from(r) }

        // Ask homescan.js to clean up the ideas
        return JSCore.must("homescan.cleanIdeas", CleanInput(raw: value, max: limit))
    }
}
