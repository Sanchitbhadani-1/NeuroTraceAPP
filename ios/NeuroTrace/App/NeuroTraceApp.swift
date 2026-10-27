// NEUROTRACEAPP.SWIFT IS WHERE THE APP STARTS
// IT MAKES THE MAIN APP MODEL AND SHOWS THE ROOT VIEW, WHICH PICKS THE SCREEN, THE TAB BAR AND THE OVERLAYS

import SwiftUI
import UIKit

// The app itself
@main
struct NeuroTraceApp: App {

    // The main app model
    @State private var app: AppModel

    // Load the fonts and make the main app model
    init() {
        Fonts.register()
        _app = State(initialValue: AppModel())
    }

    // One window that shows the root view with the app model and the light or dark setting
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.colorScheme)
        }
    }
}


// An empty view that sets the window to light, dark or automatic
private struct WindowStyle: UIViewRepresentable {

    // The theme name, "light", "dark" or "auto"
    let theme: String

    // Make the empty view
    func makeUIView(context: Context) -> UIView { StyleProbe() }

    // Pass the theme to the view and apply it
    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? StyleProbe)?.theme = theme
        (uiView as? StyleProbe)?.apply()
    }

    // The empty view that changes its window's style
    private final class StyleProbe: UIView {

        // The theme name, "auto" at first
        var theme = "auto"

        // Apply the theme when the view is added to a window
        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        // Set the window to light for "light", dark for "dark", and automatic for anything else
        func apply() {
            window?.overrideUserInterfaceStyle = theme == "light" ? .light : theme == "dark" ? .dark : .unspecified
        }
    }
}


// The view under every screen
struct RootView: View {

    // The app model, and the light or dark mode, contrast and text size from the system
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        GeometryReader { geo in

            // Make the colors from the mode, the accent color and the contrast setting
            let palette = Palette.make(dark: scheme == .dark, accent: app.accent, moreContrast: contrast == .increased)

            // Make the text sizes from the system text size and the screen size
            let insets = geo.safeAreaInsets
            let typo = Typography(
                scale: Typography.scale(for: dynamicType),
                body: geo.size.width >= 700 ? 19 : 17,
                width: geo.size.width,
                height: geo.size.height + insets.top + insets.bottom,
                pad: UIDevice.current.userInterfaceIdiom == .pad
            )
            ZStack(alignment: .top) {

                // The background color behind everything
                palette.bg.color.ignoresSafeArea()

                // The current screen, with a new view and a slide each visit
                ZStack {
                    view(for: app.screen)
                        .id(app.visit)
                        .transition(RootView.transition(app.transition))
                }

                // The tab bar on the tab screens, along the top on an iPad and along the bottom on a phone
                if app.onTab {
                    if typo.tabsOnTop {
                        VStack(spacing: 0) {
                            TabBar(top: true, inset: insets.top)
                            Spacer(minLength: 0)
                        }
                        .ignoresSafeArea(.container, edges: .top)
                        .transition(.opacity)
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            TabBar(top: false, inset: insets.bottom)
                        }
                        .ignoresSafeArea(.container, edges: .bottom)
                        .transition(.opacity)
                    }
                }

                // The small title bar at the top, left out when the tab bar is along the top
                if !(app.onTab && typo.tabsOnTop) {
                    CompactBar(topInset: insets.top)
                        .ignoresSafeArea(.container, edges: .top)
                }

                // The short pop up messages at the bottom
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ToastView(bottomInset: insets.bottom)
                }
                .ignoresSafeArea(.container, edges: .bottom)

                // The measuring cover, shown when it isn't hidden
                if !app.measuringHidden {
                    MeasuringOverlay()
                }
            }
            // Pass the colors and text sizes to every screen and set the tint color
            .environment(\.palette, palette)
            .environment(\.typo, typo)
            .tint(palette.accent.color)
            // Set the window to the chosen theme
            .background(WindowStyle(theme: app.theme).frame(width: 0, height: 0))
            // Hand the colors to the UIKit code when the view shows and each time they change
            .onAppear { applyPalette(palette) }
            .onChange(of: palette) { _, now in applyPalette(now) }
        }
    }

    // Hand the new colors to the UIKit drawing code and tell it to redraw
    private func applyPalette(_ palette: Palette) {
        Palette.current = palette
        NotificationCenter.default.post(name: .paletteChanged, object: nil)
    }

    // The move and fade used when the screen changes
    static func transition(_ kind: ScreenTransition) -> AnyTransition {
        switch kind {

        // Come in from the right and leave to the left
        case .left:
            return .asymmetric(insertion: .opacity.combined(with: .offset(x: 32)), removal: .opacity.combined(with: .offset(x: -32)))

        // Come in from the left and leave to the right
        case .right:
            return .asymmetric(insertion: .opacity.combined(with: .offset(x: -32)), removal: .opacity.combined(with: .offset(x: 32)))

        // Come up from a little below and fade out
        default:
            return .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
        }
    }

    // The view for each screen, or nothing when there is no screen yet
    @ViewBuilder
    private func view(for screen: Screen?) -> some View {
        if let screen {
            switch screen {

            // The home screen and the check in screens
            case .home: HomeScreen()
            case .consent: ConsentScreen()
            case .about: AboutScreen()
            case .draw: DrawScreen()
            case .results: ResultsScreen()
            case .exercise: ExerciseScreen()

            // The medication screen
            case .medication: MedicationScreen()

            // The tab screens
            case .dashboard: DashboardScreen()
            case .testing: TestingScreen()
            case .training: TrainingScreen()
            case .progress: ProgressScreen()
            case .care: CareScreen()
            case .settings: SettingsScreen()
            case .error: ErrorScreen()

            // The collection mode screens
            case .collect: CollectScreen()
            case .collectDetails: CollectDetailsScreen()
            case .collectDraw: CollectDrawScreen()
            case .collectDone: CollectDoneScreen()
            }
        } else {
            Color.clear
        }
    }
}
