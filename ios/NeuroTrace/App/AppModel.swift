import SwiftUI
import UIKit

// Every screen in the app. Swift checks these names when it builds, so a typo can't send someone nowhere
enum Screen {
    case home
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
    static let tabOrder: [Screen] = []
    static let tabs = Set(tabOrder)
    static let titled = Set(tabOrder)

    // Where the app was last asked to go. go() sets it and route() acts on it
    private var requested = Route(screen: .home)
    // The screen on show and its extra detail. Nothing shows until the first route finishes
    var screen: Screen? = nil
    var param: String? = nil
    var visit = 0
    var transition = ScreenTransition.fade
    var cameFrom: Screen? = nil

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

    init() {
        Motion.app = self
        // before the first frame: the saved look, so the screen never flashes the wrong
        // theme or plays motion someone switched off
        let prefs = Store.getPrefs()
        applyTheme(prefs.theme)
        applyAccent(prefs.accent)
        Motion.applyMotion(prefs.motion)

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
        return screen
    }

    func route() async {
        let asked = requested
        let target = resolve(asked.screen, asked.param)
        if target != asked.screen { return go(target) }

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
