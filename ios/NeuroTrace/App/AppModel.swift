import SwiftUI
import UIKit

struct Scoring {
    var model: Score.Model
    var reference: Score.Reference
}

struct Choice {
    var ageChoice: String
    var bracket: String?
    var hand: String
}

struct ExportFile {
    var name: String
    var data: Data
}

// Read a file that ships inside the app, like model.json
private func bundledFile(_ fileName: String) throws -> Data {
    let name = (fileName as NSString).deletingPathExtension, ext = (fileName as NSString).pathExtension
    guard let file = Bundle.main.url(forResource: name, withExtension: ext) else {
        throw NTError("couldn't load \(fileName) (it isn't in the app bundle)")
    }
    return try Data(contentsOf: file)
}

private func loadScoring() throws -> Scoring {
    let model = try bundledFile("model.json"), reference = try bundledFile("reference.json")
    try Score.checkScoringFiles(model, reference, NTFeatures.spiralFeatureOrder)
    let unnamed = NTFeatures.spiralFeatureOrder.filter { k in Copy.measures[k] == nil }
    if !unnamed.isEmpty { throw NTError("Copy.measures has no entry for: \(unnamed.joined(separator: ", ")).") }
    return Scoring(model: try JSONDecoder().decode(Score.Model.self, from: model), reference: try JSONDecoder().decode(Score.Reference.self, from: reference))
}

// Every screen in the app. Swift checks these names when it builds, so a typo can't send someone nowhere
enum Screen {
    case home, consent, about, draw, results
    case dashboard, testing, settings, error
}

// A screen plus the one extra detail some screens need, like which exercise or which check-in
struct Route: Equatable {
    var screen: Screen
    var param: String? = nil
}

// How a screen change animates. Moving between tabs slides, the theme change reveals, the rest fade
enum ScreenTransition {
    case fade, left, right, theme
}

@MainActor
@Observable
final class AppModel {
    static let tabOrder: [Screen] = [.dashboard, .testing, .settings]
    static let tabs = Set(tabOrder)
    static let titled = Set(tabOrder + [.results])

    // Where the app was last asked to go. go() sets it and route() acts on it
    private var requested = Route(screen: .home)
    // The screen on show and its extra detail. Nothing shows until the first route finishes
    var screen: Screen? = nil
    var param: String? = nil
    var visit = 0
    var transition = ScreenTransition.fade
    var cameFrom: Screen? = nil

    var loadError: Error? = nil
    @ObservationIgnored var scoring: Task<Scoring, Error>!
    // Keeps the Firebase sign in watch going, when accounts are on
    @ObservationIgnored private var accountWatch: AnyObject?

    var choice: Choice? = nil
    var current: AssessmentRecord? = nil

    var previous: Screen? = nil

    var theme = "auto"
    var accent = "blue"
    var motion = "full"

    var toastText = ""
    var toastOK = true
    var toastShown = false
    var toastID = 0
    var measuringShown = false
    var measuringHidden = true
    var measuringOn = 0
    var compactTitle = ""
    var compactShown = false

    @ObservationIgnored lazy var home = HomeModel(app: self)
    @ObservationIgnored lazy var consent = ConsentModel(app: self)
    @ObservationIgnored lazy var about = AboutModel(app: self)
    @ObservationIgnored lazy var draw = DrawModel(app: self)
    @ObservationIgnored lazy var results = ResultsModel(app: self)
    @ObservationIgnored lazy var dashboard = DashboardModel(app: self)
    @ObservationIgnored lazy var settings = SettingsModel(app: self)

    init() {
        Motion.app = self
        // before the first frame: the saved look, so the screen never flashes the wrong
        // theme or plays motion someone switched off
        let prefs = Store.getPrefs()
        applyTheme(prefs.theme)
        applyAccent(prefs.accent)
        Motion.applyMotion(prefs.motion)

        // With accounts on, signed out in Firebase means signed out here too. That covers a deleted
        // account, and anyone still signed in from before accounts existed
        accountWatch = Accounts.watch { [weak self] signedIn in
            MainActor.assumeIsolated {
                guard let self, !signedIn, Store.getPrefs().signedIn else { return }
                Store.setPrefs { p in p.signedIn = false }
                self.current = nil
                self.go(.home)
            }
        }

        scoring = Task { try loadScoring() }
        Task {
            do {
                _ = try await self.scoring.value
            } catch {
                self.loadError = error
                print("NeuroTrace: scoring files failed to load - nothing will be scored", error)
            }
        }

        _ = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Motion.applyMotion(Store.getPrefs().motion) }
        }

        Task { await self.route() }
    }

    var colorScheme: ColorScheme? { theme == "light" ? .light : theme == "dark" ? .dark : nil }

    // Whether the tab bar shows, which it only does on the tab screens
    var onTab: Bool { screen.map { AppModel.tabs.contains($0) } ?? false }

    func go(_ screen: Screen, _ param: String? = nil) {
        let next = Route(screen: screen, param: param)
        if next == requested { return }
        requested = next
        Task { await route() }
    }

    // Where someone actually ends up when they ask for a screen, after checking sign in, consent and so on
    func resolve(_ screen: Screen, _ param: String?) -> Screen {
        let prefs = Store.getPrefs()
        if !prefs.signedIn { return screen == .consent ? screen : .home }
        if screen == .home { return .dashboard }
        if screen == .error { return loadError != nil ? screen : .dashboard }
        if !prefs.consented && screen != .consent { return .consent }
        if screen == .draw && choice == nil { return .about }
        if screen == .results && current == nil && (param ?? "").isEmpty { return .dashboard }
        return screen
    }

    func route() async {
        let asked = requested
        let target = resolve(asked.screen, asked.param)
        if target != asked.screen { return go(target) }

        if asked.screen == .draw || asked.screen == .results {
            do {
                _ = try await scoring.value
            } catch {
                return go(.error)
            }
            if requested != asked { return }
        }
        show(asked.screen, asked.param)
    }

    func show(_ screen: Screen, _ param: String?) {
        let from = previous.flatMap { AppModel.tabOrder.firstIndex(of: $0) } ?? -1
        let to = AppModel.tabOrder.firstIndex(of: screen) ?? -1
        let kind: ScreenTransition = from >= 0 && to >= 0 && from != to ? (to > from ? .left : .right) : .fade
        Motion.swap(kind) { self.showNow(screen, param) }
    }

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

    private func onShow(_ screen: Screen, _ param: String?) {
        switch screen {
        case .home: home.onShow()
        case .consent: consent.onShow()
        case .about: about.onShow()
        case .draw: draw.onShow()
        case .results: results.onShow(param)
        case .dashboard: dashboard.onShow()
        case .settings: settings.onShow()
        case .testing, .error: break
        }
    }

    func titleChanged(_ frame: TitleFrame?) {
        guard let frame, let screen, AppModel.titled.contains(screen) else {
            if compactShown { compactShown = false }
            return
        }
        if compactTitle != frame.text { compactTitle = frame.text }
        let show = frame.maxY < 44 && frame.minY < 0
        if show != compactShown { compactShown = show }
    }

    func applyTheme(_ theme: String) {
        self.theme = theme
        let style: UIUserInterfaceStyle = theme == "light" ? .light : theme == "dark" ? .dark : .unspecified
        for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap({ $0.windows }) {
            window.overrideUserInterfaceStyle = style
        }
    }

    func applyAccent(_ accent: String) {
        self.accent = accent
    }
}

@MainActor
func vibrate(_ ms: Int) {
    UIImpactFeedbackGenerator(style: ms > 10 ? .medium : .light).impactOccurred()
}

func isoNow() -> String {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.string(from: Date())
}

func jsonForExport<T: Encodable>(_ value: T, pretty: Bool) -> Data {
    let encoder = JSONEncoder()
    encoder.userInfo[.forExport] = true
    encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
    encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    guard let data = try? encoder.encode(value) else { return Data() }
    let text = String(decoding: data, as: UTF8.self)
        .replacingOccurrences(of: "\"NaN\"", with: "null")
        .replacingOccurrences(of: "\"-Infinity\"", with: "null")
        .replacingOccurrences(of: "\"Infinity\"", with: "null")
    return Data(text.utf8)
}

@MainActor
func topViewController() -> UIViewController? {
    var top = Motion.keyWindow()?.rootViewController
    while let next = top?.presentedViewController { top = next }
    return top
}

// Exports are written to Store.exportsFolder for the share sheet to read. The last export is removed
// when the next one is made, and Delete all my data removes the folder
@MainActor
func shareFile(_ file: ExportFile) async -> Bool {
    let folder = Store.exportsFolder
    let url = folder.appendingPathComponent(file.name)
    do {
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try file.data.write(to: url, options: .atomic)
    } catch {
        print("NeuroTrace: couldn't write the export", error)
        return false
    }
    guard let top = topViewController() else { return false }
    return await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // Resumed only once, even if the share sheet reports back twice
        var answered = false
        sheet.completionWithItemsHandler = { _, completed, _, _ in
            if answered { return }
            answered = true
            done.resume(returning: completed)
        }
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 120, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
    }
}

// Asks before something that can't be undone. The question goes on top and the red button says what will happen
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
