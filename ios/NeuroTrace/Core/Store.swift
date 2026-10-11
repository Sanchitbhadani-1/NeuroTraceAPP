import Foundation

protocol Keyed {
    var id: Int? { get set }
}

extension AssessmentRecord: Keyed {}

enum Store {

    struct Prefs: Codable, Equatable {
        var onboarded = false
        var consented = false
        var signedIn = false
        var ageChoice: String? = nil
        var hand = "right"
        var theme = "auto"
        var accent = "blue"
        var motion = "auto"
    }

    static let dbName = "neurotrace"
    static let dbVersion = 1
    static let storeAssessments = "assessments"

    static let rawKeep = 3

    // Tests point this at a fresh folder. The tables already read belong to the old one, so they're dropped
    static var folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(dbName, isDirectory: true) {
        didSet {
            lock.lock()
            open = [:]
            lock.unlock()
        }
    }
    static var defaults = UserDefaults.standard

    private struct Table<Row: Codable>: Codable {
        var version = Store.dbVersion
        var nextId = 1
        var rows: [Row] = []
    }

    private static let lock = NSLock()
    private static var open: [String: Any] = [:]

    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return (encoder, decoder)
    }

    private static func openDb<Row: Codable>(_ name: String) throws -> Table<Row> {
        if let table = open[name] as? Table<Row> { return table }
        let url = folder.appendingPathComponent("\(name).json")
        let table = FileManager.default.fileExists(atPath: url.path)
            ? try coder().1.decode(Table<Row>.self, from: Data(contentsOf: url))
            : Table<Row>()
        open[name] = table
        return table
    }

    private static func transaction<Row: Codable, R>(_ name: String, _ mode: String, _ body: (inout Table<Row>) throws -> R) throws -> R {
        lock.lock()
        defer { lock.unlock() }
        var table: Table<Row> = try openDb(name)
        let result = try body(&table)
        if mode == "readwrite" {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try coder().0.encode(table).write(to: folder.appendingPathComponent("\(name).json"), options: .atomic)
            open[name] = table
        }
        return result
    }

    private static func add<Row: Codable & Keyed>(_ table: inout Table<Row>, _ record: Row) -> Int {
        var row = record
        let id = table.nextId
        row.id = id
        table.nextId += 1
        table.rows.append(row)
        return id
    }

    static func saveAssessment(_ record: AssessmentRecord) async throws -> Int {
        try transaction(storeAssessments, "readwrite") { (store: inout Table<AssessmentRecord>) in
            let id = add(&store, record)
            var seen = 0
            for i in store.rows.indices.reversed() {
                seen += 1
                if seen > rawKeep, let trials = store.rows[i].trials {
                    store.rows[i].trials = trials.map { trial in
                        var rest = trial
                        rest.samples = nil
                        rest.strokeStarts = nil
                        return rest
                    }
                }
            }
            return id
        }
    }

    static func listAssessments() async throws -> [AssessmentRecord] {
        let all = try transaction(storeAssessments, "readonly") { (store: inout Table<AssessmentRecord>) in store.rows }
        return all.filter { r in r.result != nil }.reversed()
    }

    static func getAssessment(_ id: Int) async throws -> AssessmentRecord? {
        try transaction(storeAssessments, "readonly") { (store: inout Table<AssessmentRecord>) in
            store.rows.first { r in r.id == id }
        }
    }

    static func clearAssessments() async throws {
        try transaction(storeAssessments, "readwrite") { (store: inout Table<AssessmentRecord>) in
            store.rows.removeAll()
        }
    }

    static func clearPersonalData() async throws {
        try await clearAssessments()
        setPrefs { p in
            p.ageChoice = prefsDefaults.ageChoice
            p.hand = prefsDefaults.hand
        }
        try? FileManager.default.removeItem(at: exportsFolder)
    }

    // Where shareFile writes a file for the share sheet
    static var exportsFolder = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)

    static let prefsKey = "neurotrace:prefs"
    static let prefsDefaults = Prefs(onboarded: false, consented: false, signedIn: false, ageChoice: nil, hand: "right", theme: "auto", accent: "blue", motion: "auto")

    static func getPrefs() -> Prefs {
        do {
            let raw = defaults.string(forKey: prefsKey)
            return raw != nil ? try JSONDecoder().decode(Prefs.self, from: Data(raw!.utf8)) : prefsDefaults
        } catch {
            return prefsDefaults
        }
    }

    static func setPrefs(_ patch: (inout Prefs) -> Void) {
        do {
            var prefs = getPrefs()
            patch(&prefs)
            defaults.set(String(decoding: try JSONEncoder().encode(prefs), as: UTF8.self), forKey: prefsKey)
        } catch {
        }
    }
}

extension Store.Prefs {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = Store.Prefs()
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? base.onboarded
        consented = try c.decodeIfPresent(Bool.self, forKey: .consented) ?? base.consented
        signedIn = try c.decodeIfPresent(Bool.self, forKey: .signedIn) ?? base.signedIn
        ageChoice = try c.decodeIfPresent(String.self, forKey: .ageChoice) ?? base.ageChoice
        hand = try c.decodeIfPresent(String.self, forKey: .hand) ?? base.hand
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? base.theme
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? base.accent
        motion = try c.decodeIfPresent(String.self, forKey: .motion) ?? base.motion
    }
}
