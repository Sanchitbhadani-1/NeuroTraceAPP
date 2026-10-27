// STORE.SWIFT SAVES AND LOADS EVERYTHING THE APP KEEPS ON THE DEVICE
// CHECK INS, RESEARCH SESSIONS, PRACTICE TRIES AND DOSES GO IN JSON FILES
// THE MEDICATION, PRACTICE LEVELS AND SETTINGS GO IN USERDEFAULTS

import Foundation

// A saved row that gets an id
protocol Keyed {
    var id: Int? { get set }
}

// The row types saved in the JSON files
extension AssessmentRecord: Keyed {}
extension CollectedSession: Keyed {}
extension TrainingTry: Keyed {}
extension Dose: Keyed {}

// Saves and loads the app's data
enum Store {

    // The person's settings
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

    // The medicine's name and the schedule the person typed in
    struct Medication: Codable, Equatable {
        var name = ""
        var schedule = ""
    }

    // One research participant, with how many sessions they have and when the last one was
    struct Subject: Equatable {
        var subjectId: String
        var sessions: Int
        var lastAt: String
    }

    // The folder name, the file version, and the name of each saved table
    static let dbName = "neurotrace"
    static let dbVersion = 3
    static let storeAssessments = "assessments"
    static let storeCollected = "collected"
    static let storeTraining = "training"
    static let storeDoses = "doses"

    // How many of the newest check ins keep their raw drawing samples
    static let rawKeep = 3

    // The folder the tables are saved in
    // Changing it drops the tables already read
    static var folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(dbName, isDirectory: true) {
        didSet {
            lock.lock()
            open = [:]
            lock.unlock()
        }
    }

    // Where the smaller settings are saved
    static var defaults = UserDefaults.standard


    // THE SAVED TABLES

    // One saved table, with its version, the next id to give, and its rows
    private struct Table<Row: Codable>: Codable {
        var version = Store.dbVersion
        var nextId = 1
        var rows: [Row] = []
    }

    // The lock around the tables, and the tables already read, by name
    private static let lock = NSLock()
    private static var open: [String: Any] = [:]

    // A JSON encoder and decoder that write and read NaN and infinity as words
    private static func coder() -> (JSONEncoder, JSONDecoder) {
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return (encoder, decoder)
    }

    // Give back a table, from memory if it was read already, from its file if there is one, or a new empty one
    private static func openDb<Row: Codable>(_ name: String) throws -> Table<Row> {
        if let table = open[name] as? Table<Row> { return table }
        let url = folder.appendingPathComponent("\(name).json")
        let table = FileManager.default.fileExists(atPath: url.path)
            ? try coder().1.decode(Table<Row>.self, from: Data(contentsOf: url))
            : Table<Row>()
        open[name] = table
        return table
    }

    // Run body on a table while holding the lock
    // In "readwrite" mode, save the changed table to its file afterward
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

    // Give a row the next id, add it to the table, and give back the id
    private static func add<Row: Codable & Keyed>(_ table: inout Table<Row>, _ record: Row) -> Int {
        var row = record
        let id = table.nextId
        row.id = id
        table.nextId += 1
        table.rows.append(row)
        return id
    }


    // CHECK INS

    // Save a check in and give back its id
    static func saveAssessment(_ record: AssessmentRecord) async throws -> Int {
        try transaction(storeAssessments, "readwrite") { (store: inout Table<AssessmentRecord>) in
            let id = add(&store, record)

            // Going from newest to oldest, remove the samples and stroke starts from every check in after the first rawKeep
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

    // Give back every check in that has a result, newest first
    static func listAssessments() async throws -> [AssessmentRecord] {
        let all = try transaction(storeAssessments, "readonly") { (store: inout Table<AssessmentRecord>) in store.rows }
        return all.filter { r in r.result != nil }.reversed()
    }

    // Give back the check in with this id, or nil
    static func getAssessment(_ id: Int) async throws -> AssessmentRecord? {
        try transaction(storeAssessments, "readonly") { (store: inout Table<AssessmentRecord>) in
            store.rows.first { r in r.id == id }
        }
    }

    // Delete every check in
    static func clearAssessments() async throws {
        try transaction(storeAssessments, "readwrite") { (store: inout Table<AssessmentRecord>) in
            store.rows.removeAll()
        }
    }

    // Delete the person's own data, which is check ins, practice tries and levels, doses, the medication,
    // the home scan consent, tap tests, home scans, the age group and hand, and the exported files
    // Research sessions and the other settings stay
    static func clearPersonalData() async throws {
        try await clearAssessments()
        try transaction(storeTraining, "readwrite") { (store: inout Table<TrainingTry>) in store.rows.removeAll() }
        try transaction(storeDoses, "readwrite") { (store: inout Table<Dose>) in store.rows.removeAll() }
        for key in [trainingKey, medicationKey, homeScanConsentKey] { defaults.removeObject(forKey: key) }
        clearTapTests()
        clearHomeScans()

        // Put the age group and hand back to their starting values
        setPrefs { p in
            p.ageChoice = prefsDefaults.ageChoice
            p.hand = prefsDefaults.hand
        }
        try? FileManager.default.removeItem(at: exportsFolder)
    }

    // Where shareFile writes a file for the share sheet
    static var exportsFolder = FileManager.default.temporaryDirectory.appendingPathComponent("exports", isDirectory: true)


    // RESEARCH SESSIONS

    // Save a collection mode session and give back its id
    static func saveCollected(_ session: CollectedSession) async throws -> Int {
        try transaction(storeCollected, "readwrite") { (store: inout Table<CollectedSession>) in
            add(&store, session)
        }
    }

    // Give back every collection mode session, newest first
    static func listCollected() async throws -> [CollectedSession] {
        let all = try transaction(storeCollected, "readonly") { (store: inout Table<CollectedSession>) in store.rows }
        return all.reversed()
    }

    // Mark the sessions with these ids as exported
    static func markExported(_ ids: [Int]) async throws {
        let idSet = Set(ids)
        try transaction(storeCollected, "readwrite") { (store: inout Table<CollectedSession>) in
            for i in store.rows.indices {
                if let id = store.rows[i].id, idSet.contains(id) { store.rows[i].exported = true }
            }
        }
    }

    // Give back each participant once, with their session count and the time of their newest session
    static func subjects() async throws -> [Subject] {
        let sessions = try await listCollected()
        var bySubject: [Subject] = []
        for s in sessions {
            if let entry = bySubject.firstIndex(where: { $0.subjectId == s.subjectId }) { bySubject[entry].sessions += 1 }
            else { bySubject.append(Subject(subjectId: s.subjectId, sessions: 1, lastAt: s.collectedAt)) }
        }
        return bySubject
    }

    // Make a random 6 character hex id that isn't already in existing
    static func newSubjectId(_ existing: Set<String>) -> String {
        var id: String
        repeat {

            // Pick 3 random bytes and write each one as 2 hex characters
            var random = SystemRandomNumberGenerator()
            let bytes = (0..<3).map { _ in UInt8.random(in: 0...255, using: &random) }
            id = bytes.map { b in
                let hex = String(b, radix: 16)
                return hex.count < 2 ? "0" + hex : hex
            }.joined()
        } while existing.contains(id)
        return id
    }


    // PRACTICE TRIES

    // Save a practice try and give back its id
    static func saveTrainingTry(_ record: TrainingTry) async throws -> Int {
        try transaction(storeTraining, "readwrite") { (store: inout Table<TrainingTry>) in
            add(&store, record)
        }
    }

    // Give back the practice tries, newest first, only for one exercise if one is given
    static func listTrainingTries(_ exercise: String? = nil) async throws -> [TrainingTry] {
        let all = try transaction(storeTraining, "readonly") { (store: inout Table<TrainingTry>) in store.rows }
        return (exercise != nil ? all.filter { r in r.exercise == exercise } : all).reversed()
    }


    // DOSES

    // Save one logged dose and give back its id
    static func saveDose(_ dose: Dose) async throws -> Int {
        try transaction(storeDoses, "readwrite") { (store: inout Table<Dose>) in
            add(&store, dose)
        }
    }

    // Give back every logged dose sorted by time taken, newest first, with the higher id first for the same time
    static func listDoses() async throws -> [Dose] {
        let all = try transaction(storeDoses, "readonly") { (store: inout Table<Dose>) in store.rows }
        return all.sorted { a, b in a.ts != b.ts ? a.ts > b.ts : (a.id ?? 0) > (b.id ?? 0) }
    }

    // Delete the dose with this id
    static func deleteDose(_ id: Int) async throws {
        try transaction(storeDoses, "readwrite") { (store: inout Table<Dose>) in
            store.rows.removeAll { d in d.id == id }
        }
    }


    // SMALLER SETTINGS IN USERDEFAULTS

    // The key the medication is saved under
    static let medicationKey = "neurotrace:medication"

    // The key for whether the person agreed to send home scan photos to Gemini
    static let homeScanConsentKey = "neurotrace:homescanConsent"

    // Load the medication, or an empty one if none is saved or it can't be read
    static func getMedication() -> Medication {
        guard let raw = defaults.string(forKey: medicationKey) else { return Medication() }
        return (try? JSONDecoder().decode(Medication.self, from: Data(raw.utf8))) ?? Medication()
    }

    // Save the medication as JSON text
    static func setMedication(_ medication: Medication) {
        guard let data = try? JSONEncoder().encode(medication) else { return }
        defaults.set(String(decoding: data, as: UTF8.self), forKey: medicationKey)
    }

    // The key the practice levels are saved under
    static let trainingKey = "neurotrace:training"

    // Load the level state for every exercise, or an empty list if it can't be read
    private static func trainingStates() -> [String: Train.LevelState] {
        do {
            return try JSONDecoder().decode([String: Train.LevelState].self, from: Data((defaults.string(forKey: trainingKey) ?? "{}").utf8))
        } catch {
            return [:]
        }
    }

    // Load the level state for one exercise
    static func getTrainingState(_ exercise: String) -> Train.LevelState? { trainingStates()[exercise] }

    // Save the level state for one exercise, and do nothing if it can't be written
    static func setTrainingState(_ exercise: String, _ state: Train.LevelState) {
        do {
            var all = trainingStates()
            all[exercise] = state
            defaults.set(String(decoding: try JSONEncoder().encode(all), as: UTF8.self), forKey: trainingKey)
        } catch {
        }
    }

    // The key the settings are saved under, and the starting settings
    static let prefsKey = "neurotrace:prefs"
    static let prefsDefaults = Prefs(onboarded: false, consented: false, signedIn: false, ageChoice: nil, hand: "right", theme: "auto", accent: "blue", motion: "auto")

    // Load the settings, or the starting settings if none are saved or they can't be read
    static func getPrefs() -> Prefs {
        do {
            let raw = defaults.string(forKey: prefsKey)
            return raw != nil ? try JSONDecoder().decode(Prefs.self, from: Data(raw!.utf8)) : prefsDefaults
        } catch {
            return prefsDefaults
        }
    }

    // Load the settings, change them with patch, and save them, doing nothing if they can't be written
    static func setPrefs(_ patch: (inout Prefs) -> Void) {
        do {
            var prefs = getPrefs()
            patch(&prefs)
            defaults.set(String(decoding: try JSONEncoder().encode(prefs), as: UTF8.self), forKey: prefsKey)
        } catch {
        }
    }
}

// Read the settings from JSON, using the starting value for any missing field
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
