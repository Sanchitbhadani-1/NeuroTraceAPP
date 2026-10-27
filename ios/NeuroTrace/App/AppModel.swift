// APPMODEL.SWIFT HOLDS THE MAIN APP MODEL THAT EVERY SCREEN SHARES
// IT DECIDES WHICH SCREEN SHOWS, LOADS THE SCORING FILES, AND HAS HELPERS FOR SHARING FILES AND ASKING TO CONFIRM

import SwiftUI
import UIKit

// The scoring model and the reference group, read from model.json and reference.json
struct Scoring {
    var model: Score.Model
    var reference: Score.Reference
}

// The age, age bracket and hand picked before a check in
struct Choice {
    var ageChoice: String
    var bracket: String?
    var hand: String
}

// The details typed in for one person in collection mode
struct CollectDetails {
    var consent: Bool
    var age: Int?
    var hand: String?
    var diagnosis: String?
    var medicationHoursAgo: Double?
}

// The collection mode session being recorded, with its spirals, details and saved copy
struct Collecting {
    var subjectId: String
    var session: Int
    var trials: [Trace] = []
    var details: CollectDetails? = nil
    var saved: CollectedSession? = nil
}

// A file to share, with its name and contents
struct ExportFile {
    var name: String
    var data: Data
}

// Read a file that ships inside the app, like model.json
private func bundledFile(_ fileName: String) throws -> Data {

    // Split the name from the extension and find the file in the app
    let name = (fileName as NSString).deletingPathExtension, ext = (fileName as NSString).pathExtension
    guard let file = Bundle.main.url(forResource: name, withExtension: ext) else {
        throw NTError("couldn't load \(fileName) (it isn't in the app bundle)")
    }
    return try Data(contentsOf: file)
}

// Load and check model.json and reference.json, then decode them into a Scoring
private func loadScoring() throws -> Scoring {

    // Read both files and check that they match the list of spiral measures
    let model = try bundledFile("model.json"), reference = try bundledFile("reference.json")
    try Score.checkScoringFiles(model, reference, NTFeatures.spiralFeatureOrder)

    // Throw an error if any measure has no name in Copy.measures
    let unnamed = NTFeatures.spiralFeatureOrder.filter { k in Copy.measures[k] == nil }
    if !unnamed.isEmpty { throw NTError("Copy.measures has no entry for: \(unnamed.joined(separator: ", ")).") }

    // Decode both files
    return Scoring(model: try JSONDecoder().decode(Score.Model.self, from: model), reference: try JSONDecoder().decode(Score.Reference.self, from: reference))
}

// Every screen in the app
enum Screen {
    case home, consent, about, draw, results, exercise, medication
    case dashboard, testing, training, progress, care, settings, error
    case collect, collectDetails, collectDraw, collectDone

    // True for the collection mode screens, where a facilitator records spirals for the reference group
    var isCollection: Bool { [.collect, .collectDetails, .collectDraw, .collectDone].contains(self) }
}

// A screen plus the one extra detail some screens need, like which exercise or which check in
struct Route: Equatable {
    var screen: Screen
    var param: String? = nil
}

// How a screen change animates, with a fade, a slide left or right, or the theme reveal
enum ScreenTransition {
    case fade, left, right, theme
}

// The main app model that every screen shares
@MainActor
@Observable
final class AppModel {

    // The tab screens in order, the same screens as a set, and the screens with a big title
    static let tabOrder: [Screen] = [.dashboard, .testing, .training, .progress, .care, .settings]
    static let tabs = Set(tabOrder)
    static let titled = Set(tabOrder + [.results, .medication])

    // Where the app was last asked to go, set by go() and used by route()
    private var requested = Route(screen: .home)

    // The screen on show and its extra detail, or nil until the first route finishes
    var screen: Screen? = nil
    var param: String? = nil

    // How many screens have shown, how the last change animated, and the screen before this one
    var visit = 0
    var transition = ScreenTransition.fade
    var cameFrom: Screen? = nil

    // The error from loading the scoring files, and the task that loads them
    var loadError: Error? = nil
    @ObservationIgnored var scoring: Task<Scoring, Error>!

    // The Firebase sign in listener, when accounts are on
    @ObservationIgnored private var accountWatch: AnyObject?

    // The picked age and hand, the check in on show, and the collection session being recorded
    var choice: Choice? = nil
    var current: AssessmentRecord? = nil
    var collecting: Collecting? = nil

    // The last screen shown
    var previous: Screen? = nil

    // The theme, accent color and motion setting
    var theme = "auto"
    var accent = "blue"
    var motion = "full"

    // The toast message, whether it is a good or bad message, whether it shows, and a number that goes up with each new toast
    var toastText = ""
    var toastOK = true
    var toastShown = false
    var toastID = 0

    // Whether the measuring card shows, and how many of its steps are lit
    var measuringShown = false
    var measuringHidden = true
    var measuringOn = 0

    // The small title in the top bar and whether it shows
    var compactTitle = ""
    var compactShown = false

    // The model for each screen, made the first time it is used
    @ObservationIgnored lazy var home = HomeModel(app: self)
    @ObservationIgnored lazy var consent = ConsentModel(app: self)
    @ObservationIgnored lazy var about = AboutModel(app: self)
    @ObservationIgnored lazy var draw = DrawModel(app: self)
    @ObservationIgnored lazy var results = ResultsModel(app: self)
    @ObservationIgnored lazy var dashboard = DashboardModel(app: self)
    @ObservationIgnored lazy var training = TrainingModel(app: self)
    @ObservationIgnored lazy var exercise = ExerciseModel(app: self)
    @ObservationIgnored lazy var progress = ProgressModel(app: self)
    @ObservationIgnored lazy var settings = SettingsModel(app: self)
    @ObservationIgnored lazy var collect = CollectModel(app: self)
    @ObservationIgnored lazy var medication = MedicationModel(app: self)
    @ObservationIgnored lazy var care = CareModel(app: self)

    // Set up the app when it starts
    init() {
        Motion.app = self

        // Apply the saved theme, accent color and motion setting
        let prefs = Store.getPrefs()
        applyTheme(prefs.theme)
        applyAccent(prefs.accent)
        Motion.applyMotion(prefs.motion)

        // When Firebase says nobody is signed in but the app says someone is, sign out here and go home
        accountWatch = Accounts.watch { [weak self] signedIn in
            MainActor.assumeIsolated {
                guard let self, !signedIn, Store.getPrefs().signedIn else { return }
                Store.setPrefs { p in p.signedIn = false }
                self.current = nil
                self.go(.home)
            }
        }

        // Start loading the scoring files, and save the error if they fail
        scoring = Task { try loadScoring() }
        Task {
            do {
                _ = try await self.scoring.value
            } catch {
                self.loadError = error
                print("NeuroTrace: scoring files failed to load - nothing will be scored", error)
            }
        }

        // Apply the motion setting again whenever Reduce Motion is turned on or off
        _ = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Motion.applyMotion(Store.getPrefs().motion) }
        }

        // Show the first screen
        Task { await self.route() }
    }

    // Light or dark for the light and dark themes, or nil to follow the phone
    var colorScheme: ColorScheme? { theme == "light" ? .light : theme == "dark" ? .dark : nil }

    // True when the screen on show is a tab screen
    var onTab: Bool { screen.map { AppModel.tabs.contains($0) } ?? false }

    // Ask to go to a screen, doing nothing if it was already asked for
    func go(_ screen: Screen, _ param: String? = nil) {
        let next = Route(screen: screen, param: param)
        if next == requested { return }
        requested = next

        // Stop the exercise when leaving the exercise screen, then route
        if screen != .exercise { exercise.exStop() }
        Task { await route() }
    }

    // Pick the screen someone ends up on when they ask for a screen, after checking sign in, consent and so on
    func resolve(_ screen: Screen, _ param: String?) -> Screen {
        let prefs = Store.getPrefs()

        // Signed out people only see the home or consent screen
        if !prefs.signedIn { return screen == .consent ? screen : .home }

        // Home goes to the dashboard, and the error screen only shows when there is a load error
        if screen == .home { return .dashboard }
        if screen == .error { return loadError != nil ? screen : .dashboard }

        // Collection screens other than the first need a session being recorded
        if screen.isCollection { return screen == .collect || collecting != nil ? screen : .collect }

        // Go to consent if they haven't agreed yet
        if !prefs.consented && screen != .consent { return .consent }

        // Drawing needs a choice, an exercise must be built, and results need a check in to show
        if screen == .draw && choice == nil { return .about }
        if screen == .exercise && !(Train.exercises[param ?? ""]?.built ?? false) { return .training }
        if screen == .results && current == nil && (param ?? "").isEmpty { return .dashboard }
        return screen
    }

    // Go to the screen that was asked for, or to where resolve() sends it
    func route() async {
        let asked = requested
        let target = resolve(asked.screen, asked.param)
        if target != asked.screen { return go(target) }

        // The draw, results and progress screens wait for the scoring files, and go to the error screen if they fail
        if asked.screen == .draw || asked.screen == .results || asked.screen == .progress {
            do {
                _ = try await scoring.value
            } catch {
                return go(.error)
            }

            // Stop if another screen was asked for while waiting
            if requested != asked { return }
        }
        show(asked.screen, asked.param)
    }

    // Show a screen, sliding left or right between two different tabs and fading otherwise
    func show(_ screen: Screen, _ param: String?) {
        let from = previous.flatMap { AppModel.tabOrder.firstIndex(of: $0) } ?? -1
        let to = AppModel.tabOrder.firstIndex(of: screen) ?? -1
        let kind: ScreenTransition = from >= 0 && to >= 0 && from != to ? (to > from ? .left : .right) : .fade
        Motion.swap(kind) { self.showNow(screen, param) }
    }

    // Switch to the screen, hide the small title, run the screen's onShow and tell screen readers
    private func showNow(_ screen: Screen, _ param: String?) {
        cameFrom = previous
        self.screen = screen
        self.param = param
        visit += 1
        compactShown = false
        onShow(screen, param)
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        previous = screen
    }

    // Call the onShow function of the screen's model
    private func onShow(_ screen: Screen, _ param: String?) {
        switch screen {
        case .home: home.onShow()
        case .consent: consent.onShow()
        case .about: about.onShow()
        case .draw: draw.onShow()
        case .results: results.onShow(param)
        case .dashboard: dashboard.onShow()
        case .training: training.onShow()
        case .exercise: exercise.onShow(param ?? "")
        case .progress: progress.onShow()
        case .settings: settings.onShow()
        case .collect: collect.onShow()
        case .collectDetails: collect.onShowDetails()
        case .collectDraw: collect.onShowDraw()
        case .collectDone: collect.onShowDone()
        case .medication: medication.onShow()
        case .care: care.onShow()
        case .testing, .error: break
        }
    }

    // Update the small title in the top bar when the big title moves
    func titleChanged(_ frame: TitleFrame?) {

        // Hide the small title when there is no big title or the screen has none
        guard let frame, let screen, AppModel.titled.contains(screen) else {
            if compactShown { compactShown = false }
            return
        }

        // Copy the big title's text, and show the small title once the big title has scrolled up past the top 44 points
        if compactTitle != frame.text { compactTitle = frame.text }
        let show = frame.maxY < 44 && frame.minY < 0
        if show != compactShown { compactShown = show }
    }

    // Save the theme and set every window to light, dark or the phone's setting
    func applyTheme(_ theme: String) {
        self.theme = theme
        let style: UIUserInterfaceStyle = theme == "light" ? .light : theme == "dark" ? .dark : .unspecified
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }) {
            window.overrideUserInterfaceStyle = style
        }
    }

    // Save the accent color
    func applyAccent(_ accent: String) {
        self.accent = accent
    }
}

// Give a medium tap for more than 10 ms and a light tap otherwise
@MainActor
func vibrate(_ ms: Int) {
    UIImpactFeedbackGenerator(style: ms > 10 ? .medium : .light).impactOccurred()
}

// The time now as ISO 8601 text with fractions of a second
func isoNow() -> String {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.string(from: Date())
}

// Turn a value into JSON for an export, with sorted keys, and pretty printed if pretty is true
func jsonForExport<T: Encodable>(_ value: T, pretty: Bool) -> Data {
    let encoder = JSONEncoder()
    encoder.userInfo[.forExport] = true
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]

    // Write NaN and infinity as text, or give back empty data if encoding fails
    encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    guard let data = try? encoder.encode(value) else { return Data() }

    // Swap the NaN and infinity text for null
    let text = String(decoding: data, as: UTF8.self)
        .replacingOccurrences(of: "\"NaN\"", with: "null")
        .replacingOccurrences(of: "\"-Infinity\"", with: "null")
        .replacingOccurrences(of: "\"Infinity\"", with: "null")
    return Data(text.utf8)
}

// The screen on top of everything else in the key window
@MainActor
func topViewController() -> UIViewController? {
    var top = Motion.keyWindow()?.rootViewController
    while let next = top?.presentedViewController { top = next }
    return top
}

// Write a file to Store.exportsFolder and open the share sheet for it
// Give back true if it was shared, and false if it wasn't
@MainActor
func shareFile(_ file: ExportFile) async -> Bool {
    let folder = Store.exportsFolder
    let url = folder.appendingPathComponent(file.name)

    // Remove the old exports folder, make it again and write the file into it
    do {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try file.data.write(to: url, options: .atomic)
    } catch {
        print("NeuroTrace: couldn't write the export", error)
        return false
    }

    // Show the share sheet over the top screen and wait for it to close
    guard let top = topViewController() else { return false }
    return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // Answer only the first time the share sheet reports back
        var answered = false
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            if answered { return }
            answered = true
            done.resume(returning: completed)
        }

        // On iPad, show the sheet near the bottom middle of the screen with no arrow
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 120, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }
}

// Show an alert with the question, the detail, Cancel and a red button named action
// Give back true if the red button is tapped
@MainActor
func confirm(_ question: String, _ detail: String? = nil, action: String) async -> Bool {
    guard let top = topViewController() else { return false }
    return await withCheckedContinuation { (answer: CheckedContinuation<Bool, Never>) in
        let alert = UIAlertController(title: question, message: detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in answer.resume(returning: false) })
        alert.addAction(UIAlertAction(title: action, style: .destructive) { _ in answer.resume(returning: true) })
        top.present(alert, animated: true)
    }
}
