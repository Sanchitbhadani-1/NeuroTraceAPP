import SwiftUI
import UIKit

enum Icon {
    case back, chevron, lock, info, checkmark, play, redo, export
    case dashboard, testing, training, progress, care, settings
}

private let testingPoints: [CGPoint] = [
    (12.8, 12.0), (12.9, 12.3), (13.0, 12.6), (12.9, 13.0), (12.6, 13.4), (12.2, 13.7), (11.7, 13.9), (11.1, 13.9), (10.5, 13.7),
    (9.9, 13.3), (9.4, 12.8), (9.2, 12.0), (9.1, 11.1), (9.3, 10.3), (9.8, 9.4), (10.5, 8.7), (11.5, 8.3), (12.6, 8.1), (13.7, 8.2),
    (14.8, 8.7), (15.8, 9.6), (16.5, 10.7), (16.9, 12.0), (16.9, 13.4), (16.4, 14.9), (15.6, 16.1), (14.3, 17.1), (12.8, 17.8),
    (11.1, 18.0), (9.4, 17.6), (7.8, 16.8), (6.5, 15.6), (5.5, 13.9), (5.1, 12.0), (5.2, 10.0), (5.8, 8.0), (7.1, 6.3), (8.8, 5.0),
    (10.9, 4.2), (13.1, 4.0), (15.4, 4.5), (17.5, 5.6), (19.3, 7.3), (20.5, 9.5), (21.0, 12.0),
].map { (pt: (Double, Double)) in CGPoint(x: pt.0, y: pt.1) }

private func svgArc(_ path: inout Path, from p1: CGPoint, to p2: CGPoint, r: CGFloat, large: Bool, sweep: Bool) {
    let x1 = (p1.x - p2.x) / 2, y1 = (p1.y - p2.y) / 2
    var radius = r
    let lambda = (x1 * x1 + y1 * y1) / (radius * radius)
    if lambda > 1 { radius *= sqrt(lambda) }
    let sign: CGFloat = large != sweep ? 1 : -1
    let num = radius * radius * radius * radius - radius * radius * y1 * y1 - radius * radius * x1 * x1
    let den = radius * radius * y1 * y1 + radius * radius * x1 * x1
    let coef = sign * sqrt(max(0, num / den))
    let cx = coef * y1, cy = -coef * x1
    let center = CGPoint(x: cx + (p1.x + p2.x) / 2, y: cy + (p1.y + p2.y) / 2)
    let start = atan2((y1 - cy) / radius, (x1 - cx) / radius)
    let end = atan2((-y1 - cy) / radius, (-x1 - cx) / radius)
    var delta = end - start
    if sweep && delta < 0 { delta += 2 * .pi }
    if !sweep && delta > 0 { delta -= 2 * .pi }
    for i in 1...24 {
        let a = start + delta * CGFloat(i) / 24
        path.addLine(to: CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
    }
}

struct IconShape: Shape {
    let icon: Icon

    func path(in rect: CGRect) -> Path {
        var p = Path()
        func line(_ points: [CGPoint]) {
            p.move(to: points[0])
            for point in points.dropFirst() { p.addLine(to: point) }
        }
        func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
            p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: r, height: r))
        }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }
        switch icon {
        case .back:
            line([CGPoint(x: 15, y: 5), CGPoint(x: 8, y: 12), CGPoint(x: 15, y: 19)])
        case .chevron:
            line([CGPoint(x: 9, y: 5), CGPoint(x: 16, y: 12), CGPoint(x: 9, y: 19)])
        case .lock:
            rounded(5, 11, 14, 10, 2)
            p.move(to: CGPoint(x: 8, y: 11))
            p.addLine(to: CGPoint(x: 8, y: 8))
            svgArc(&p, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 16, y: 8), r: 4, large: false, sweep: true)
            p.addLine(to: CGPoint(x: 16, y: 11))
        case .info:
            circle(12, 12, 9)
            line([CGPoint(x: 12, y: 11), CGPoint(x: 12, y: 17)])
            line([CGPoint(x: 12, y: 7.5), CGPoint(x: 12, y: 7.51)])
        case .checkmark:
            line([CGPoint(x: 5, y: 12.5), CGPoint(x: 9.5, y: 17), CGPoint(x: 19, y: 7.5)])
        case .play:
            line([CGPoint(x: 7, y: 4.5), CGPoint(x: 7, y: 19.5), CGPoint(x: 20, y: 12)])
            p.closeSubpath()
        case .redo:
            line([CGPoint(x: 4, y: 4), CGPoint(x: 4, y: 10), CGPoint(x: 10, y: 10)])
            p.move(to: CGPoint(x: 5.5, y: 15))
            svgArc(&p, from: CGPoint(x: 5.5, y: 15), to: CGPoint(x: 7.1, y: 7.7), r: 7, large: true, sweep: false)
            p.addLine(to: CGPoint(x: 4, y: 10))
        case .export:
            line([CGPoint(x: 12, y: 3), CGPoint(x: 12, y: 15)])
            line([CGPoint(x: 8, y: 7), CGPoint(x: 12, y: 3), CGPoint(x: 16, y: 7)])
            p.move(to: CGPoint(x: 5, y: 12))
            p.addLine(to: CGPoint(x: 5, y: 19))
            svgArc(&p, from: CGPoint(x: 5, y: 19), to: CGPoint(x: 7, y: 21), r: 2, large: false, sweep: false)
            p.addLine(to: CGPoint(x: 17, y: 21))
            svgArc(&p, from: CGPoint(x: 17, y: 21), to: CGPoint(x: 19, y: 19), r: 2, large: false, sweep: false)
            p.addLine(to: CGPoint(x: 19, y: 12))
        case .dashboard:
            rounded(4, 4, 7, 7, 1.5)
            rounded(13, 4, 7, 7, 1.5)
            rounded(4, 13, 7, 7, 1.5)
            rounded(13, 13, 7, 7, 1.5)
        case .testing:
            line(testingPoints)
        case .training:
            rounded(5, 6, 3, 12, 1)
            rounded(16, 6, 3, 12, 1)
            rounded(2, 9, 3, 6, 1)
            rounded(19, 9, 3, 6, 1)
            line([CGPoint(x: 8, y: 12), CGPoint(x: 16, y: 12)])
        case .progress:
            line([CGPoint(x: 4, y: 20), CGPoint(x: 20, y: 20)])
            line([CGPoint(x: 5, y: 16), CGPoint(x: 9, y: 11), CGPoint(x: 12, y: 14), CGPoint(x: 18, y: 6)])
        case .care:
            // A heart, two round tops meeting a point at the bottom
            p.move(to: CGPoint(x: 12, y: 20))
            p.addLine(to: CGPoint(x: 5.35, y: 11.46))
            svgArc(&p, from: CGPoint(x: 5.35, y: 11.46), to: CGPoint(x: 12, y: 7.06), r: 4, large: true, sweep: true)
            svgArc(&p, from: CGPoint(x: 12, y: 7.06), to: CGPoint(x: 18.65, y: 11.46), r: 4, large: true, sweep: true)
            p.closeSubpath()
        case .settings:
            line([CGPoint(x: 4, y: 7), CGPoint(x: 13, y: 7)])
            line([CGPoint(x: 17, y: 7), CGPoint(x: 20, y: 7)])
            line([CGPoint(x: 4, y: 17), CGPoint(x: 7, y: 17)])
            line([CGPoint(x: 11, y: 17), CGPoint(x: 20, y: 17)])
            circle(15, 7, 2)
            circle(9, 17, 2)
        }
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 24, y: rect.height / 24))
    }
}

struct IconView: View {
    let icon: Icon
    var size: CGFloat = 24
    var weight: CGFloat = 2

    var body: some View {
        Group {
            if icon == .play {
                IconShape(icon: icon).fill()
            } else {
                IconShape(icon: icon).stroke(style: StrokeStyle(lineWidth: weight * size / 24, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct CollectModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var collectMode: Bool {
        get { self[CollectModeKey.self] }
        set { self[CollectModeKey.self] = newValue }
    }
}

enum TextKind {
    case body, lede, sub, strong, barTitle, sectionTitle, cardTitle, h3
    case h1(CGFloat, CGFloat, CGFloat)
    case brand(CGFloat)
}

private struct TextKindModifier: ViewModifier {
    let kind: TextKind
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {
        switch kind {
        case .body: content.nt(.body()).foregroundStyle(p.ink.color)
        case .lede: content.nt(.body()).foregroundStyle(p.ink2.color)
        case .sub: content.nt(.body(15, lineHeight: 1.4)).foregroundStyle(p.ink2.color)
        case .strong: content.nt(.body(nil, 600, lineHeight: 1.3)).foregroundStyle(p.ink.color)
        case .barTitle: content.nt(.body(17, 600, lineHeight: 1.3)).foregroundStyle(p.ink.color)
        case .sectionTitle, .cardTitle: content.nt(.display(21, 600, lineHeight: 1.2)).foregroundStyle(p.ink.color)
        case .h3: content.nt(.display(19, 600, lineHeight: 1.25)).foregroundStyle(p.ink.color)
        case let .h1(size, lineHeight, weight): content.nt(.display(size, weight, lineHeight: lineHeight)).foregroundStyle(p.ink.color)
        case let .brand(size): content.nt(.body(size, 600, lineHeight: 1.2)).foregroundStyle(p.ink.color)
        }
    }
}

extension View {
    func text(_ kind: TextKind) -> some View { modifier(TextKindModifier(kind: kind)) }

    func fullWidth(_ alignment: Alignment = .leading) -> some View { frame(maxWidth: .infinity, alignment: alignment) }
}

enum BtnKind {
    case primary, secondary
}

struct NTButtonStyle: ButtonStyle {
    var kind: BtnKind
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        NTButtonBody(configuration: configuration, kind: kind, compact: compact)
    }
}

private struct NTButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: BtnKind
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.palette) private var p
    @Environment(\.collectMode) private var collect

    var body: some View {
        let pressed = configuration.isPressed && isEnabled && !Motion.reduced()
        configuration.label
            .nt(.body(collect && !compact ? 19 : 17, 600, lineHeight: 1.2))
            .multilineTextAlignment(.center)
            .foregroundStyle(!isEnabled ? p.ink2.color : kind == .primary ? Color.white : p.accent.color)
            .padding(.horizontal, compact ? 20 : 24)
            .padding(.vertical, compact ? 0 : 8)
            .frame(maxWidth: compact ? nil : CGFloat.infinity, minHeight: compact ? 48 : (collect ? 64 : 56))
            .background(Capsule().fill(!isEnabled ? p.fill.color : kind == .primary ? p.accentFill.color : Color.clear))
            .overlay(Capsule().strokeBorder(isEnabled && kind == .secondary ? p.accent.color : Color.clear, lineWidth: 1.5))
            .contentShape(Capsule())
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(pressed ? 0.8 : 1)
            .animation(Theme.ease(120), value: pressed)
    }
}

struct Btn: View {
    let title: String
    var kind: BtnKind = .primary
    var icon: Icon? = nil
    var compact = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { IconView(icon: icon, size: compact ? 16 : 22, weight: 2.2) }
                Text(title)
            }
        }
        .buttonStyle(NTButtonStyle(kind: kind, compact: compact))
        .disabled(disabled)
    }
}

struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var dim = true

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !Motion.reduced()
        return configuration.label
            .scaleEffect(pressed ? scale : 1)
            .opacity(pressed && dim ? 0.8 : 1)
            .animation(Theme.ease(120), value: pressed)
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat? = nil
    var spacing: CGFloat? = nil
    var alignment: HorizontalAlignment = .leading
    var fill = false
    @ViewBuilder var content: () -> Content
    @Environment(\.palette) private var p
    @Environment(\.collectMode) private var collect

    var body: some View {
        VStack(alignment: alignment, spacing: spacing ?? (collect ? 16 : 12)) { content() }
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: alignment == .center ? .top : .topLeading)
            .padding(padding ?? (collect ? 28 : 20))
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.surface.color))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.line.color, lineWidth: p.hair))
    }
}

struct Hairline: View {
    @Environment(\.palette) private var p

    var body: some View {
        Rectangle().fill(p.line.color).frame(height: p.hair).frame(maxWidth: .infinity)
    }
}

struct LockNote: View {
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconView(icon: .lock, size: 20).padding(.top, 1)
            Text(Copy.onDevice).nt(.body(15, lineHeight: 1.4))
        }
        .foregroundStyle(p.ink2.color)
    }
}

struct TitleFrame: Equatable {
    var text: String
    var minY: CGFloat
    var maxY: CGFloat
}

struct TitleKey: PreferenceKey {
    static let defaultValue: TitleFrame? = nil
    static func reduce(value: inout TitleFrame?, nextValue: () -> TitleFrame?) {
        value = value ?? nextValue()
    }
}

struct H1: View {
    let text: String
    var size: CGFloat = 34
    var lineHeight: CGFloat = 1.1
    var top: CGFloat = 16
    var weight: CGFloat = 500

    var body: some View {
        Text(text)
            .text(.h1(size, lineHeight, weight))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, top)
            .accessibilityAddTraits(.isHeader)
            .screenTitle(text)
    }
}

extension View {
    // Marks this as the screen's title, for the small title bar that slides in once it scrolls away.
    // The first one on a screen wins
    func screenTitle(_ text: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: TitleKey.self, value: TitleFrame(text: text, minY: geo.frame(in: .global).minY, maxY: geo.frame(in: .global).maxY))
        })
    }
}

struct ScreenView<Content: View>: View {
    var maxWidth: CGFloat = 560
    var tabbed = false
    var titled = false
    var padTop: CGFloat? = nil
    @ViewBuilder var content: (ScrollViewProxy) -> Content
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            // Room for the tab bar, along the top on an iPad and along the bottom on a phone
            let barOnTop = tabbed && typo.tabsOnTop
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) { content(proxy) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, padTop ?? (barOnTop ? insets.top + TabBar.topHeight + 16 : max(insets.top, 24)))
                        .padding(.leading, max(insets.leading, 24))
                        .padding(.trailing, max(insets.trailing, 24))
                        .padding(.bottom, tabbed && !barOnTop ? max(insets.bottom, 8) + 104 : max(insets.bottom, 24))
                        .frame(maxWidth: maxWidth)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height + insets.top + insets.bottom, alignment: .top)
                }
                .scrollIndicators(.hidden)
            }
            .ignoresSafeArea(.container)
        }
        .onPreferenceChange(TitleKey.self) { value in
            MainActor.assumeIsolated {
                app.titleChanged(titled ? value : nil)
            }
        }
    }
}

struct TabBar: View {
    var top: Bool
    // The status bar above a top bar, or the home indicator below a bottom bar
    var inset: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo
    @Namespace private var lensSpace

    // How tall the top bar is under the status bar, so screens can leave room for it
    static let topHeight: CGFloat = 64

    static let items: [(id: Screen, label: String, icon: Icon)] = [
    ]

    var body: some View {
        if top { topBar } else { bottomBar }
    }

    // Dashboard comes first and bigger, since it's the home page. Then the tabs, then settings as a button at the end
    private var topBar: some View {
        let middle = Self.items.filter { item in item.id != .dashboard && item.id != .settings }
        // Narrow iPad windows show the middle tabs as icons only, so nothing gets squeezed
        let labeled = typo.width >= 760
        return HStack(spacing: 12) {
            homeTab
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(middle, id: \.id) { item in pill(item, labeled: labeled) }
            }
            Spacer(minLength: 0)
            pill(Self.items[Self.items.count - 1], labeled: false)
        }
        .padding(.horizontal, 20)
        .padding(.top, inset)
        .frame(height: inset + Self.topHeight)
        .frame(maxWidth: .infinity)
        .background(p.surface.color)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var homeTab: some View {
        let current = app.screen == .dashboard
        return Button {
            app.go(.dashboard)
        } label: {
            HStack(spacing: 10) {
                Mascot(mood: "idle").frame(width: 32, height: 32)
                Text("Dashboard").nt(.body(21, 600, lineHeight: 1)).lineLimit(1)
            }
            .foregroundStyle(current ? p.accent.color : p.ink.color)
            .padding(.leading, 8)
            .padding(.trailing, 18)
            .frame(minHeight: 48)
            .background {
                if current { Capsule().fill(p.accentSoft.color).matchedGeometryEffect(id: "lens", in: lensSpace) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.95, dim: false))
        .accessibilityLabel("Dashboard")
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }

    private func pill(_ item: (id: Screen, label: String, icon: Icon), labeled: Bool) -> some View {
        let current = app.screen == item.id
        return Button {
            app.go(item.id)
        } label: {
            HStack(spacing: 8) {
                IconView(icon: item.icon, size: 22)
                if labeled { Text(item.label).nt(.body(16, 600, lineHeight: 1)).lineLimit(1) }
            }
            .foregroundStyle(current ? p.accent.color : p.ink2.color)
            .padding(.horizontal, labeled ? 14 : 11)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                if current { Capsule().fill(p.accentSoft.color).matchedGeometryEffect(id: "lens", in: lensSpace) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.95, dim: false))
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }

    // A phone fits five along the bottom. Settings opens from the button at the top of the dashboard instead
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(Self.items.filter { item in item.id != .settings }, id: \.id) { item in
                let current = app.screen == item.id
                Button {
                    app.go(item.id)
                } label: {
                    VStack(spacing: 6) {
                        IconView(icon: item.icon, size: 24)
                        Text(item.label).nt(.body(15, 600, lineHeight: 1)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(current ? p.accent.color : p.ink2.color)
                    .frame(maxWidth: typo.width >= 700 ? CGFloat(160) : CGFloat.infinity, minHeight: 58)
                    .background(alignment: .top) {
                        if current {
                            Capsule()
                                .fill(p.accentSoft.color)
                                .frame(width: 64, height: 32)
                                .matchedGeometryEffect(id: "lens", in: lensSpace)
                                .padding(.top, 3)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.95, dim: false))
                .accessibilityAddTraits(current ? [.isSelected] : [])
            }
        }
        .padding(.top, 6)
        .padding(.horizontal, 12)
        .padding(.bottom, max(inset, 8))
        .frame(maxWidth: .infinity)
        .background(p.surface.color)
        .overlay(alignment: .top) { Hairline() }
    }
}

struct CompactBar: View {
    var topInset: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let shown = app.compactShown
        Text(app.compactTitle)
            .nt(.body(nil, 600, lineHeight: 1.3))
            .foregroundStyle(p.ink.color)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 64)
            .padding(.top, max(topInset, 10))
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .bottom)
            .background(p.bg.color)
            .overlay(alignment: .bottom) { Hairline() }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : -(max(topInset, 10) + 44))
            .animation(Motion.reduced() ? nil : Theme.ease(380), value: shown)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct ToastView: View {
    var bottomInset: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @State private var drawn: CGFloat = 0

    var body: some View {
        let shown = app.toastShown
        HStack(spacing: 8) {
            if app.toastOK {
                IconShape(icon: .checkmark)
                    .trim(from: 0, to: drawn)
                    .stroke(style: StrokeStyle(lineWidth: 2.6 * 20 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
            } else {
                IconView(icon: .info, size: 20, weight: 2.2)
            }
            Text(app.toastText).nt(.body(15, 600, lineHeight: 1.3))
        }
        .foregroundStyle(p.bg.color)
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .background(Capsule().fill(p.ink.color))
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || Motion.reduced() ? 1 : 0.96)
        .offset(y: shown || Motion.reduced() ? 0 : 16)
        .padding(.bottom, max(bottomInset, 8) + 88)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .onChange(of: app.toastID) { _, _ in
            drawn = 0
            if Motion.reduced() {
                drawn = 1
                return
            }
            withAnimation(Theme.ease(380).delay(0.14)) { drawn = 1 }
        }
    }
}

struct MeasuringOverlay: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let shown = app.measuringShown
        ZStack {
            p.bg.color.ignoresSafeArea()
            VStack(spacing: 14) {
                Mascot(mood: "thinking").frame(width: 120, height: 120)
                Text(Copy.measuring).nt(.body(24, 600, lineHeight: 1.3)).foregroundStyle(p.ink.color)
                // one row per Copy.measureSteps
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<Copy.measureSteps.count, id: \.self) { i in
                        let on = i < app.measuringOn
                        HStack(spacing: 12) {
                            ZStack {
                                if on {
                                    Circle().fill(p.accent.color)
                                    IconView(icon: .checkmark, size: 15, weight: 3).foregroundStyle(Color.white)
                                } else {
                                    Circle().strokeBorder(p.guide.color, lineWidth: 2)
                                }
                            }
                            .frame(width: 24, height: 24)
                            Text(Copy.measureSteps[i]).nt(.body()).foregroundStyle(on ? p.ink.color : p.ink2.color)
                        }
                        .opacity(on ? 1 : 0.45)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .frame(maxWidth: 360)
            .offset(y: shown ? 0 : 14)
            .scaleEffect(shown ? 1 : 0.97)
            .padding(24)
        }
        .opacity(shown ? 1 : 0)
        .accessibilityElement(children: .combine)
    }
}
