import SwiftUI
import UIKit

@main
struct NeuroTraceApp: App {
    @State private var app: AppModel

    init() {
        Fonts.register()
        _app = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.colorScheme)
        }
    }
}

private struct WindowStyle: UIViewRepresentable {
    let theme: String

    func makeUIView(context: Context) -> UIView { StyleProbe() }

    func updateUIView(_ uiView: UIView, context: Context) {
        (uiView as? StyleProbe)?.theme = theme
        (uiView as? StyleProbe)?.apply()
    }

    private final class StyleProbe: UIView {
        var theme = "auto"

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            window?.overrideUserInterfaceStyle = theme == "light" ? .light : theme == "dark" ? .dark : .unspecified
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        GeometryReader { geo in
            let palette = Palette.make(dark: scheme == .dark, accent: app.accent, moreContrast: contrast == .increased)
            let insets = geo.safeAreaInsets
            let typo = Typography(
                scale: Typography.scale(for: dynamicType),
                body: geo.size.width >= 700 ? 19 : 17,
                width: geo.size.width,
                height: geo.size.height + insets.top + insets.bottom,
                pad: UIDevice.current.userInterfaceIdiom == .pad
            )
            ZStack(alignment: .top) {
                palette.bg.color.ignoresSafeArea()

                ZStack {
                    view(for: app.screen)
                        .id(app.visit)
                        .transition(RootView.transition(app.transition))
                }

                // compact title bar: the screen's h1, shown once the large title scrolls away.
                // Not under a top tab bar, which already names the screen
                if !(app.onTab && typo.tabsOnTop) {
                    CompactBar(topInset: insets.top)
                        .ignoresSafeArea(.container, edges: .top)
                }

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    ToastView(bottomInset: insets.bottom)
                }
                .ignoresSafeArea(.container, edges: .bottom)

                // shown while a finished check-in is scored and saved (Motion.measuring()).
                if !app.measuringHidden {
                    MeasuringOverlay()
                }
            }
            .environment(\.palette, palette)
            .environment(\.typo, typo)
            .tint(palette.accent.color)
            .background(WindowStyle(theme: app.theme).frame(width: 0, height: 0))
            .onAppear { applyPalette(palette) }
            .onChange(of: palette) { _, now in applyPalette(now) }
        }
    }

    // Hand the new colors to the UIKit drawing code and tell it to redraw
    private func applyPalette(_ palette: Palette) {
        Palette.current = palette
        NotificationCenter.default.post(name: .paletteChanged, object: nil)
    }

    static func transition(_ kind: ScreenTransition) -> AnyTransition {
        switch kind {
        case .left:
            return .asymmetric(insertion: .opacity.combined(with: .offset(x: 32)), removal: .opacity.combined(with: .offset(x: -32)))
        case .right:
            return .asymmetric(insertion: .opacity.combined(with: .offset(x: -32)), removal: .opacity.combined(with: .offset(x: 32)))
        default:
            return .asymmetric(insertion: .opacity.combined(with: .offset(y: 12)), removal: .opacity)
        }
    }

    // One view per screen. Nothing shows until the first route finishes
    @ViewBuilder
    private func view(for screen: Screen?) -> some View {
        if let screen {
            switch screen {
            case .home: HomeScreen()
            }
        } else {
            Color.clear
        }
    }
}
