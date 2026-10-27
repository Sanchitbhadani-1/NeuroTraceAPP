// HOMESCANTESTS.SWIFT CHECKS THE HOME SCAN IDEAS AND HOW THEY ARE SAVED
// IT CLEANS GEMINI'S IDEAS THE SAME WAY APP/TOOLS/HOMESCAN-CHECK.MJS CHECKS THEM

import Foundation
import XCTest
// Use the NeuroTraceCore module when it exists, or the app if it doesn't
#if canImport(NeuroTraceCore)
@testable import NeuroTraceCore
#else
@testable import NeuroTrace
#endif

// Makes one idea with a title, a reason, a place and a high priority, with any extra fields replacing those
private func idea(_ title: Any, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["title": title, "why": "Edges catch a foot.", "where": "front left", "priority": "high"].merging(extra) { _, new in new }
}

// Makes a scan of a living room with the given ideas, with any extra fields replacing those
private func scan(_ ideas: Any, _ extra: [String: Any] = [:]) -> [String: Any] {
    ["isRoom": true, "room": "living room", "ideas": ideas].merging(extra) { _, new in new }
}

// Turns an object into JSON text
private func text(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

// The tests for the home scan
final class HomeScanTests: XCTestCase {

    // Check how Gemini's answer is cleaned into ideas
    func testCleanIdeas() {

        // Check that a clean answer gives the same idea as an object, as text, or as text in a code block
        do {
            let raw = scan([idea("Move the rug out of the walkway")])
            for input in [raw, text(raw), "```json\n" + text(raw) + "\n```"] as [Any] {
                let r = HomeScanRules.cleanIdeas(raw: input)
                XCTAssertEqual(r.status, "ok")
                XCTAssertEqual(r.room, "living room")
                XCTAssertEqual(r.ideas, [HomeIdea(title: "Move the rug out of the walkway", why: "Edges catch a foot.", place: "front left", priority: "high", done: false)])
            }
        }

        // Check that plain text or nothing is unreadable, isRoom false is not a room with no ideas, and no ideas list is empty
        XCTAssertEqual(HomeScanRules.cleanIdeas(raw: "Sorry, I can't help with that."), HomeScanResult(status: "unreadable", room: "", ideas: [], dropped: 0))
        XCTAssertEqual(HomeScanRules.cleanIdeas(raw: nil).status, "unreadable")
        XCTAssertEqual(HomeScanRules.cleanIdeas(raw: scan([idea("Move the rug")], ["isRoom": false])).status, "notRoom")
        XCTAssertEqual(HomeScanRules.cleanIdeas(raw: scan([idea("Move the rug")], ["isRoom": false])).ideas.count, 0)
        XCTAssertEqual(HomeScanRules.cleanIdeas(raw: scan("rug")).status, "empty")
        XCTAssertEqual(HomeScanRules.cleanIdeas(raw: scan([Any]())).status, "empty")

        // Check that isRoom set to 0 still counts as a room, and only false itself means not a room
        XCTAssertEqual(HomeScanRules.cleanIdeas(raw: "{\"isRoom\": 0, \"ideas\": [{\"title\": \"Add a lamp\"}]}").status, "ok")

        // Check that broken items are dropped, and a kept idea with missing fields gets empty text and medium priority
        do {
            let r = HomeScanRules.cleanIdeas(raw: scan([NSNull(), "rug", [String: Any](), ["title": "  "], ["title": 7], ["title": "Add a night light"]] as [Any]))
            XCTAssertEqual(r.ideas.map { i in i.title }, ["Add a night light"])
            XCTAssertEqual(r.ideas[0].why, "")
            XCTAssertEqual(r.ideas[0].place, "")
            XCTAssertEqual(r.ideas[0].priority, "medium")
            XCTAssertEqual(r.dropped, 5)
        }

        // Check that extra spaces are squeezed, priority is made lowercase, and an unknown priority becomes medium
        do {
            let r = HomeScanRules.cleanIdeas(raw: scan([idea("  Tape   down\nthe cord ", ["priority": "HIGH"]), idea("Add a lamp", ["priority": "urgent"])]))
            XCTAssertEqual(r.ideas[0].title, "Tape down the cord")
            XCTAssertEqual(r.ideas[0].priority, "high")
            XCTAssertEqual(r.ideas[1].priority, "medium")
        }

        // Check that long text is cut at a space and ends with "…"
        do {
            let long = "Move the heavy wooden coffee table closer to the wall so there is a wide clear path from the door to the sofa"
            let r = HomeScanRules.cleanIdeas(raw: scan([idea(long, ["why": String(repeating: long, count: 4)])]))
            let title = r.ideas[0].title, why = r.ideas[0].why

            // Check that the title is at most 80 characters and is cut between words
            XCTAssertTrue(title.utf16.count <= 80 && title.hasSuffix("…"), title)
            XCTAssertTrue(long.hasPrefix(String(title.dropLast())), "cut mid-word: \(title)")
            XCTAssertEqual(Array(long.utf16)[title.utf16.count - 1], UInt16(UInt8(ascii: " ")), "cut mid-word: \(title)")

            // Check that the reason is at most 200 characters and the room name at most 40
            XCTAssertTrue(why.utf16.count <= 200 && why.hasSuffix("…"))
            let rooms = HomeScanRules.cleanIdeas(raw: scan([idea("x", ["room": String(repeating: "a", count: 100)])], ["room": String(repeating: "b", count: 100)]))
            XCTAssertTrue(rooms.room.utf16.count <= 40)
        }

        // Check that ideas that differ only in capitals, spaces or end marks are kept once
        do {
            let r = HomeScanRules.cleanIdeas(raw: scan([idea("Move the rug"), idea("move the rug."), idea("Move the  rug!")]))
            XCTAssertEqual(r.ideas.count, 1)
            XCTAssertEqual(r.dropped, 2)
        }

        // Check that at most 6 ideas are kept, or the max given, and the rest are counted as dropped
        do {
            let nine = (0..<9).map { i in idea("Idea \(i)") }
            XCTAssertEqual(HomeScanRules.cleanIdeas(raw: scan(nine)).ideas.count, 6)
            XCTAssertEqual(HomeScanRules.cleanIdeas(raw: scan(nine), max: 3).ideas.count, 3)
            XCTAssertEqual(HomeScanRules.cleanIdeas(raw: scan(nine)).dropped, 3)
        }

        // Check the banned words
        do {

            // Ideas with a banned word in the title, reason or place
            let banned = [
                idea("This prevents falls"),
                idea("Makes your home safe"),
                idea("Improve the lighting"),
                idea("Add rails", ["why": "Guarantees you won't trip."]),
                idea("Add rails", ["where": "Ensures a steady grip"]),
                idea("Clear the floor", ["why": "Common for people with Parkinson's."]),
                idea("A quick safety inspection"),
                idea("Proven to reduce trips"),
                idea("Effective for balance"),
            ]

            // Ideas with words that look close to banned words but are allowed
            let kept = [
                idea("Secure the loose cord"),
                idea("Provide a lamp by the bed"),
                idea("Stand up slowly from the low chair"),
                idea("Move the cord behind the TV screen"),
                idea("Add a grab bar by the safety rail"),
            ]

            // Check that only the allowed ideas are kept and every banned one is dropped
            let r = HomeScanRules.cleanIdeas(raw: scan(banned + kept), max: 20)
            XCTAssertEqual(r.ideas.map { i in i.title }, kept.map { i in i["title"] as! String })
            XCTAssertEqual(r.dropped, banned.count)

            // Check that banned ideas don't count toward the max
            XCTAssertEqual(HomeScanRules.cleanIdeas(raw: scan(banned + kept), max: 2).ideas.first?.title, "Secure the loose cord")
        }

        // Check isBanned on its own
        XCTAssertTrue(HomeScanRules.isBanned("This prevents falls"))
        XCTAssertFalse(HomeScanRules.isBanned("Secure the loose cord"))
        print("HOMESCAN OK")
    }

    // Check that home scans save, load and clear
    func testHomeScanStore() {

        // Use empty test settings, and put the real ones back at the end
        let suite = "neurotrace-homescans-check-\(UUID().uuidString)"
        let saved = Store.defaults
        Store.defaults = UserDefaults(suiteName: suite)!
        defer {
            Store.defaults.removePersistentDomain(forName: suite)
            Store.defaults = saved
        }

        // Check that there are no scans at first, and a saved scan loads back the same
        XCTAssertEqual(Store.getHomeScans(), [])
        let first = HomeScan(ts: 5, room: "Bathroom", ideas: [HomeIdea(title: "Keep a clear path through the room", why: "Things on the floor are easy to trip over.", place: "Walkways", priority: "medium", done: false)])
        Store.setHomeScans([first])
        XCTAssertEqual(Store.getHomeScans(), [first])

        // Check that the saved text names the place field "where"
        XCTAssertTrue(Store.defaults.string(forKey: Store.homeScansKey)!.contains("\"where\""))

        // Check that clearing removes every scan
        Store.clearHomeScans()
        XCTAssertEqual(Store.getHomeScans(), [])
        print("HOMESCAN STORE OK")
    }
}
