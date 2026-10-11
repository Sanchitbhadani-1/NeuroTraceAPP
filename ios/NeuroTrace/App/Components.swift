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

func handDrawn(_ r1: Double, _ turns: Double, _ steps: Int) -> [[Double]] {
    spiralPoints(0, r1, turns, steps).enumerated().map { (i, pt) -> [Double] in
        let x: Double = pt[0], y: Double = pt[1]
        let p: Double = Double(i) / Double(steps)
        let th: Double = p * turns * 2 * Double.pi
        let w1: Double = 0.6 * sin(th * 0.45 + 1.3), w2: Double = 0.3 * sin(th * 1.3 + 2.73), w3: Double = 0.1 * sin(th * 3.7 + 0.91)
        let wobble: Double = 4 * (w1 + w2 + w3)
        let dr: Double = (wobble + 0.4 * sin(Double(i) * 2.39996)) * min(1, p * 5)
        return [x + dr * cos(th), y + dr * sin(th)]
    }
}

enum Art {
    static let mark = spiralPoints(0, 150, 2.25, 120)
    static let guide = spiralPoints(0, 150, 4, 720)
    static let trace = handDrawn(150, 4, 720)
}

struct ArtShape: Shape {
    let points: [[Double]]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (i, pt) in points.enumerated() {
            let q = CGPoint(x: rect.minX + (170 + pt[0]) * rect.width / 340, y: rect.minY + (170 + pt[1]) * rect.height / 340)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }
}

struct MarkView: View {
    var size: CGFloat = 28
    var color: Color? = nil
    @Environment(\.palette) private var p

    var body: some View {
        ArtShape(points: Art.mark)
            .stroke(color ?? p.accent.color, style: StrokeStyle(lineWidth: 30 * size / 340, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct MiniArt: View {
    var size: CGFloat = 92
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            ArtShape(points: Art.guide).stroke(p.guide.color, lineWidth: 7 * size / 340)
            ArtShape(points: Art.trace).stroke(p.accent.color, style: StrokeStyle(lineWidth: 13 * size / 340, lineCap: .round, lineJoin: .round))
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

// Two buttons side by side and the same size, like at the end of the results. When the row is too narrow
// for their words, they stack, both full width
struct ButtonPair<First: View, Second: View>: View {
    @ViewBuilder var first: () -> First
    @ViewBuilder var second: () -> Second

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { first(); second() }
            VStack(spacing: 12) { first(); second() }
        }
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

struct BackLink: View {
    var label = "Back"
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                IconView(icon: .back, size: 24, weight: 2.2)
                Text(label).nt(.body(17, lineHeight: 1.5))
            }
            .foregroundStyle(p.accent.color)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, -8)
    }
}

struct BarLink: View {
    let label: String
    var strong = false
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            Text(label)
                .nt(.body(17, strong ? 600 : 400, lineHeight: 1.5))
                .foregroundStyle(p.accent.color)
                .frame(minWidth: 44, minHeight: 44, alignment: strong ? .trailing : .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct Bar<Left: View, Center: View, Right: View>: View {
    var side: CGFloat = 88
    @ViewBuilder var left: () -> Left
    @ViewBuilder var center: () -> Center
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack(spacing: 0) {
            left().frame(width: side, alignment: .leading)
            center().frame(maxWidth: .infinity).multilineTextAlignment(.center)
            right().frame(width: side, alignment: .trailing).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
    }
}

struct Segments: View {
    let total: Int
    let done: Int
    var width: CGFloat = 120
    var height: CGFloat = 5
    var gap: CGFloat = 6
    var animateNow = true
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<total, id: \.self) { i in
                if i <= done {
                    GrowBar(color: p.accent.color, height: height, grow: animateNow && i == done)
                } else {
                    Capsule().fill(p.fill.color).frame(height: height)
                }
            }
        }
        .frame(width: width)
        .accessibilityElement()
        .accessibilityLabel("\(done) of \(total)")
    }
}

private struct GrowBar: View {
    let color: Color
    let height: CGFloat
    let grow: Bool
    @State private var shown = false

    var body: some View {
        Capsule().fill(color).frame(height: height)
            .scaleEffect(x: grow && !shown ? 0 : 1, y: 1, anchor: .leading)
            .onAppear {
                if !grow || Motion.reduced() { shown = true; return }
                withAnimation(Theme.ease(560)) { shown = true }
            }
    }
}

struct Chip: View {
    let label: String
    let checked: Bool
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if checked {
                    IconView(icon: .checkmark, size: 17, weight: 3)
                        .transition(.scale(scale: 0).combined(with: .opacity))
                }
                Text(label)
            }
            .nt(.body(nil, checked ? 600 : 400, lineHeight: 1.2))
            .multilineTextAlignment(.center)
            .foregroundStyle(p.ink.color)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(checked ? p.accentSoft.color : p.surface.color))
            .overlay(Capsule().strokeBorder(checked ? p.accent.color : p.line.color, lineWidth: checked ? 2 : p.hair))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .animation(Motion.reduced() ? nil : Theme.ease(260), value: checked)
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}

struct ChipGrid: View {
    let items: [(value: String, label: String)]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {
        let rows = stride(from: 0, to: items.count, by: 2).map { i in Array(items[i..<min(i + 2, items.count)]) }
        VStack(spacing: 10) {
            ForEach(0..<rows.count, id: \.self) { r in
                HStack(spacing: 10) {
                    ForEach(rows[r], id: \.value) { item in
                        Chip(label: item.label, checked: selected == item.value) { onSelect(item.value) }
                    }
                }
            }
        }
        .padding(.top, 12)
    }
}

struct Legend: View {
    let text: String
    var value: String? = nil
    @Environment(\.palette) private var p

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text).text(.strong)
            Spacer(minLength: 0)
            if let value { Text(value).nt(.body()).foregroundStyle(p.ink2.color) }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

struct Segmented: View {
    let options: [(value: String, label: String)]
    let selected: String?
    let onSelect: (String, CGPoint) -> Void
    @Environment(\.palette) private var p
    @Namespace private var thumbSpace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { i in
                let on = options[i].value == selected
                Text(options[i].label)
                    .nt(.body(16, on ? 600 : 400, lineHeight: 1.2))
                    .foregroundStyle(p.ink.color)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(p.segThumb.color)
                                .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 2)
                                .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .global) { location in onSelect(options[i].value, location) }
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
                    .accessibilityAction { onSelect(options[i].value, .zero) }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.fill.color))
        .animation(Motion.reduced() ? nil : Theme.ease(300), value: selected)
        .padding(.top, 12)
    }
}

struct CheckBox: View {
    let checked: Bool
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {
            // accentFill, so the white checkmark stands out in dark mode too
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(checked ? p.accentFill.color : p.surface.color)
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(checked ? p.accentFill.color : p.ink2.color.opacity(0.6), lineWidth: 2)
            if checked {
                IconView(icon: .checkmark, size: 20, weight: 3).foregroundStyle(Color.white)
            }
        }
        .frame(width: 26, height: 26)
        .scaleEffect(checked ? 1 : 0.94)
        .animation(Motion.reduced() ? nil : Theme.ease(260), value: checked)
    }
}

struct CheckRow: View {
    let text: String
    // A smaller line under the text, inside the same tap target
    var detail: String? = nil
    let checked: Bool
    var compact = false
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(alignment: detail == nil ? .center : .top, spacing: 16) {
                CheckBox(checked: checked)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text).nt(.body(nil, lineHeight: 1.35)).foregroundStyle(p.ink.color).multilineTextAlignment(.leading)
                    if let detail, !detail.isEmpty {
                        Text(detail).text(.sub).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: compact ? 0 : 72)
            .padding(.vertical, compact ? 0 : 14)
            .padding(.horizontal, compact ? 0 : 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}

@MainActor
@Observable
final class Shaker {
    var x: CGFloat = 0
    @ObservationIgnored private var frame = 0

    func shake() {
        if Motion.reduced() { return }
        Frames.cancel(frame)
        let start = Frames.now()
        func step(_ now: Double) {
            let u = min(1, (now - start) / 440)
            x = u >= 1 ? 0 : CGFloat(CubicBezier.keyframes(u, [(0, 0), (0.2, -7), (0.4, 6), (0.6, -3), (0.8, 2), (0.9999, 0)], .brand))
            if u < 1 { frame = Frames.next(step) }
        }
        frame = Frames.next(step)
    }
}

struct StatusBox: View {
    let sentence: String?
    let shake: CGFloat
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        if let sentence {
            let cut = sentence.firstIndex(of: ".").map { sentence.index(after: $0) } ?? sentence.startIndex
            Card(padding: 0) {
                HStack(alignment: .top, spacing: 12) {
                    IconView(icon: .info, size: 22).foregroundStyle(p.accent.color)
                    (ntText(String(sentence[..<cut]), .body(15, 600, lineHeight: 1.4), typo) + ntText(String(sentence[cut...]), .body(15, lineHeight: 1.4), typo))
                        .lineSpacing(lineGap(.body(15, lineHeight: 1.4), typo))
                        .foregroundStyle(p.ink.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            .offset(x: shake)
            .padding(.top, 16)
            .accessibilityElement(children: .combine)
        }
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
        (.dashboard, "Dashboard", .dashboard),
        (.testing, "Testing", .testing),
        (.settings, "Settings", .settings),
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

struct Track: View {
    let dots: [(frac: Double, then: Bool)]
    var active = true
    @Environment(\.palette) private var p
    @State private var settled = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2).fill(p.fill.color).frame(width: w, height: 4).offset(y: 8)
                RoundedRectangle(cornerRadius: 1).fill(p.guide.color).frame(width: 2, height: 14).offset(x: w / 2 - 1, y: 3)
                ForEach(0..<dots.count, id: \.self) { i in
                    let d = dots[i]
                    let at = settled ? min(max(jsRound(d.frac * 100) / 100, 0.03), 0.97) : 0.5
                    ZStack {
                        if d.then {
                            Circle().fill(p.surface.color)
                            Circle().strokeBorder(p.accent.color, lineWidth: 3)
                        } else {
                            Circle().fill(p.accent.color)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(p.surface.color).padding(-3))
                    .offset(x: w * CGFloat(at) - 10)
                    .opacity(settled ? 1 : 0)
                }
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .accessibilityHidden(true)
        .onAppear { if active { settle() } }
        .onChange(of: active) { _, now in if now { settle() } }
    }

    private func settle() {
        if settled { return }
        if Motion.reduced() {
            settled = true
            return
        }
        withAnimation(Theme.ease(640)) { settled = true }
    }
}

struct Reveal: ViewModifier {
    let index: Int
    var onIn: (@MainActor () -> Void)? = nil
    @State private var shown = false
    @Environment(\.typo) private var typo

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { check(geo.frame(in: .global)) }
                    .onChange(of: geo.frame(in: .global).minY) { _, _ in check(geo.frame(in: .global)) }
            })
    }

    private func check(_ frame: CGRect) {
        if shown { return }
        if Motion.reduced() {
            shown = true
            onIn?()
            return
        }
        if frame.minY < typo.height * 0.94 && frame.maxY > 0 {
            withAnimation(Theme.ease(600).delay(Double(index % 6) * 0.07)) { shown = true }
            onIn?()
        }
    }
}

extension View {
    func reveal(_ index: Int, onIn: (@MainActor () -> Void)? = nil) -> some View { modifier(Reveal(index: index, onIn: onIn)) }
}

func ntText(_ string: String, _ font: NTFont, _ typo: Typography) -> Text {
    Text(string).font(Font(Fonts.make(font, size: typo.scaled(font.size ?? typo.body)) as CTFont))
}

func lineGap(_ font: NTFont, _ typo: Typography) -> CGFloat {
    let size = typo.scaled(font.size ?? typo.body)
    return max(0, size * font.lineHeight - Fonts.make(font, size: size).lineHeight)
}
