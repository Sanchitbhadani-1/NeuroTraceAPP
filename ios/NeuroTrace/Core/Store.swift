import Foundation

protocol Keyed {
    var id: Int? { get set }
}

extension AssessmentRecord: Keyed {}
extension CollectedSession: Keyed {}
extension TrainingTry: Keyed {}

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

    struct Subject: Equatable {
        var subjectId: String
        var sessions: Int
        var lastAt: String
    }

    static let dbName = "neurotrace"
    static let dbVersion = 2
    static let storeAssessments = "assessments"
    static let storeCollected = "collected"
    static let storeTraining = "training"

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
        try transaction(storeTraining, "readwrite") { (store: inout Table<TrainingTry>) in store.rows.removeAll() }
        for key in [trainingKey] { defaults.removeObject(forKey: key) }
        setPrefs { p in
            p.ageChoice = prefsDefaults.ageChoice
            p.hand = prefsDefaults.hand
        }
        try? FileManager.default.removeItem(at: exportsFolder)
    }

    // Where shareFile writes a file for the share sheet
    static var exportsFolder = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)

    static func saveCollected(_ session: CollectedSession) async throws -> Int {
        try transaction(storeCollected, "readwrite") { (store: inout Table<CollectedSession>) in
            add(&store, session)
        }
    }

    static func listCollected() async throws -> [CollectedSession] {
        let all = try transaction(storeCollected, "readonly") { (store: inout Table<CollectedSession>) in store.rows }
        return all.reversed()
    }

    static func markExported(_ ids: [Int]) async throws {
        let idSet = Set(ids)
        try transaction(storeCollected, "readwrite") { (store: inout Table<CollectedSession>) in
            for i in store.rows.indices {
                if let id = store.rows[i].id, idSet.contains(id) { store.rows[i].exported = true }
            }
        }
    }

    static func subjects() async throws -> [Subject] {
        let sessions = try await listCollected()
        var bySubject: [Subject] = []
        for s in sessions {
            if let entry = bySubject.firstIndex(where: { $0.subjectId == s.subjectId }) { bySubject[entry].sessions += 1 }
            else { bySubject.append(Subject(subjectId: s.subjectId, sessions: 1, lastAt: s.collectedAt)) }
        }
        return bySubject
    }

    static func newSubjectId(_ existing: Set<String>) -> String {
        var id: String
        repeat {
            var random = SystemRandomNumberGenerator()
            let bytes = (0..<3).map { _ in UInt8.random(in: 0...255, using: &random) }
            id = bytes.map { b in
                let hex = String(b, radix: 16)
                return hex.count < 2 ? "0" + hex : hex
            }.joined()
        } while existing.contains(id)
        return id
    }

    static func saveTrainingTry(_ record: TrainingTry) async throws -> Int {
        try transaction(storeTraining, "readwrite") { (store: inout Table<TrainingTry>) in
            add(&store, record)
        }
    }

    static func listTrainingTries(_ exercise: String? = nil) async throws -> [TrainingTry] {
        let all = try transaction(storeTraining, "readonly") { (store: inout Table<TrainingTry>) in store.rows }
        return (exercise != nil ? all.filter { r in r.exercise == exercise } : all).reversed()
    }

    static let trainingKey = "neurotrace:training"

    private static func trainingStates() -> [String: Train.LevelState] {
        do {
            return try JSONDecoder().decode([String: Train.LevelState].self, from: Data((defaults.string(forKey: trainingKey) ?? "{}").utf8))
        } catch {
            return [:]
        }
    }

    static func getTrainingState(_ exercise: String) -> Train.LevelState? { trainingStates()[exercise] }

    static func setTrainingState(_ exercise: String, _ state: Train.LevelState) {
        do {
            var all = trainingStates()
            all[exercise] = state
            defaults.set(String(decoding: try JSONEncoder().encode(all), as: UTF8.self), forKey: trainingKey)
        } catch {
        }
    }

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
