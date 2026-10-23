import Foundation

// Home safety scan rules. Aryan's app/homescan.js checks Gemini's ideas, called through JSCore

enum HomeScanRules {
    static let maxIdeas: Int = JSCore.must("homescan.MAX_IDEAS")
    static let priorities: [String] = JSCore.must("homescan.PRIORITIES")

    private struct Limits: Decodable {
        var title: Int
        var why: Int
        var place: Int
        var room: Int

        enum CodingKeys: String, CodingKey {
            case title, why, room
            case place = "where"
        }
    }

    static let limits: (title: Int, why: Int, place: Int, room: Int) = {
        let l: Limits = JSCore.must("homescan.LIMITS")
        return (title: l.title, why: l.why, place: l.place, room: l.room)
    }()

    // ClaimsRules. An idea using any of homescan.js's banned words is dropped, not reworded
    static func isBanned(_ text: String) -> Bool {
        JSCore.must("helpers.isBanned", text)
    }

    private struct CleanInput: Encodable {
        var raw: JSONValue?
        var max: Int
    }

    // Check the AI's ideas before anything is shown. raw is the model's text, or a reply that's already
    // parsed (the tests pass both, like homescan-check.mjs)
    static func cleanIdeas(raw: Any?, max limit: Int = maxIdeas) -> HomeScanResult {
        let value: JSONValue? = raw.flatMap { r in (r as? String).map { text in .string(text) } ?? JSONValue.from(r) }
        return JSCore.must("homescan.cleanIdeas", CleanInput(raw: value, max: limit))
    }
}
