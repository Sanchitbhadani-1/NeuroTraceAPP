// COMPONENTS.SWIFT HOLDS THE BUTTONS, CARDS AND OTHER PIECES THE SCREENS ARE BUILT FROM
// IT ALSO HOLDS THE ICONS, THE SPIRAL ART, THE TAB BAR, THE TOAST AND THE MEASURING SCREEN

import SwiftUI
import UIKit


// THE ICONS

// Every icon the app can draw
enum Icon {
    case back, chevron, lock, info, checkmark, play, redo, export
    case dashboard, testing, training, progress, care, settings
}

// The points of the small spiral in the Testing icon, on a 24 by 24 grid
private let testingPoints: [CGPoint] = [
    (12.8, 12.0), (12.9, 12.3), (13.0, 12.6), (12.9, 13.0), (12.6, 13.4), (12.2, 13.7), (11.7, 13.9), (11.1, 13.9), (10.5, 13.7),
    (9.9, 13.3), (9.4, 12.8), (9.2, 12.0), (9.1, 11.1), (9.3, 10.3), (9.8, 9.4), (10.5, 8.7), (11.5, 8.3), (12.6, 8.1), (13.7, 8.2),
    (14.8, 8.7), (15.8, 9.6), (16.5, 10.7), (16.9, 12.0), (16.9, 13.4), (16.4, 14.9), (15.6, 16.1), (14.3, 17.1), (12.8, 17.8),
    (11.1, 18.0), (9.4, 17.6), (7.8, 16.8), (6.5, 15.6), (5.5, 13.9), (5.1, 12.0), (5.2, 10.0), (5.8, 8.0), (7.1, 6.3), (8.8, 5.0),
    (10.9, 4.2), (13.1, 4.0), (15.4, 4.5), (17.5, 5.6), (19.3, 7.3), (20.5, 9.5), (21.0, 12.0),
].map { (pt: (Double, Double)) in CGPoint(x: pt.0, y: pt.1) }

// Add a curved arc from p1 to p2 to the path, the same way an SVG arc works, using 24 short lines
private func svgArc(_ path: inout Path, from p1: CGPoint, to p2: CGPoint, r: CGFloat, large: Bool, sweep: Bool) {

    // Half the distance between the two ends, and grow the radius if it is too small to reach
    let x1 = (p1.x - p2.x) / 2, y1 = (p1.y - p2.y) / 2
    var radius = r
    let lambda = (x1 * x1 + y1 * y1) / (radius * radius)
    if lambda > 1 { radius *= sqrt(lambda) }

    // Find the center of the circle the arc is on
    let sign: CGFloat = large != sweep ? 1 : -1
    let num = radius * radius * radius * radius - radius * radius * y1 * y1 - radius * radius * x1 * x1
    let den = radius * radius * y1 * y1 + radius * radius * x1 * x1
    let coef = sign * sqrt(max(0, num / den))
    let cx = coef * y1, cy = -coef * x1
    let center = CGPoint(x: cx + (p1.x + p2.x) / 2, y: cy + (p1.y + p2.y) / 2)

    // Find the start and end angles, and the turn between them in the sweep direction
    let start = atan2((y1 - cy) / radius, (x1 - cx) / radius)
    let end = atan2((-y1 - cy) / radius, (-x1 - cx) / radius)
    var delta = end - start
    if sweep && delta < 0 { delta += 2 * .pi }
    if !sweep && delta > 0 { delta -= 2 * .pi }

    // Draw the arc as 24 short lines
    for i in 1...24 {
        let a = start + delta * CGFloat(i) / 24
        path.addLine(to: CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a)))
    }
}


// The outline of one icon, drawn on a 24 by 24 grid and stretched to fit
struct IconShape: Shape {

    // Which icon to draw
    let icon: Icon

    func path(in rect: CGRect) -> Path {
        var p = Path()

        // Draw a line through a list of points
        func line(_ points: [CGPoint]) {
            p.move(to: points[0])
            for point in points.dropFirst() { p.addLine(to: point) }
        }

        // Draw a rounded box
        func rounded(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) {
            p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: r, height: r))
        }

        // Draw a circle around a center point
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
            p.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
        }

        // Draw the lines and shapes for each icon
        switch icon {
        case .back:

            // An arrow pointing left
            line([CGPoint(x: 15, y: 5), CGPoint(x: 8, y: 12), CGPoint(x: 15, y: 19)])
        case .chevron:

            // An arrow pointing right
            line([CGPoint(x: 9, y: 5), CGPoint(x: 16, y: 12), CGPoint(x: 9, y: 19)])
        case .lock:

            // A box with a curved loop on top
            rounded(5, 11, 14, 10, 2)
            p.move(to: CGPoint(x: 8, y: 11))
            p.addLine(to: CGPoint(x: 8, y: 8))
            svgArc(&p, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 16, y: 8), r: 4, large: false, sweep: true)
            p.addLine(to: CGPoint(x: 16, y: 11))
        case .info:

            // A circle with a line and a dot in it
            circle(12, 12, 9)
            line([CGPoint(x: 12, y: 11), CGPoint(x: 12, y: 17)])
            line([CGPoint(x: 12, y: 7.5), CGPoint(x: 12, y: 7.51)])
        case .checkmark:

            // A checkmark
            line([CGPoint(x: 5, y: 12.5), CGPoint(x: 9.5, y: 17), CGPoint(x: 19, y: 7.5)])
        case .play:

            // A triangle pointing right
            line([CGPoint(x: 7, y: 4.5), CGPoint(x: 7, y: 19.5), CGPoint(x: 20, y: 12)])
            p.closeSubpath()
        case .redo:

            // A corner arrow and a curve going around
            line([CGPoint(x: 4, y: 4), CGPoint(x: 4, y: 10), CGPoint(x: 10, y: 10)])
            p.move(to: CGPoint(x: 5.5, y: 15))
            svgArc(&p, from: CGPoint(x: 5.5, y: 15), to: CGPoint(x: 7.1, y: 7.7), r: 7, large: true, sweep: false)
            p.addLine(to: CGPoint(x: 4, y: 10))
        case .export:

            // An arrow pointing up out of an open box with rounded corners
            line([CGPoint(x: 12, y: 3), CGPoint(x: 12, y: 15)])
            line([CGPoint(x: 8, y: 7), CGPoint(x: 12, y: 3), CGPoint(x: 16, y: 7)])
            p.move(to: CGPoint(x: 5, y: 12))
            p.addLine(to: CGPoint(x: 5, y: 19))
            svgArc(&p, from: CGPoint(x: 5, y: 19), to: CGPoint(x: 7, y: 21), r: 2, large: false, sweep: false)
            p.addLine(to: CGPoint(x: 17, y: 21))
            svgArc(&p, from: CGPoint(x: 17, y: 21), to: CGPoint(x: 19, y: 19), r: 2, large: false, sweep: false)
            p.addLine(to: CGPoint(x: 19, y: 12))
        case .dashboard:

            // Four small rounded squares in a grid
            rounded(4, 4, 7, 7, 1.5)
            rounded(13, 4, 7, 7, 1.5)
            rounded(4, 13, 7, 7, 1.5)
            rounded(13, 13, 7, 7, 1.5)
        case .testing:

            // A small spiral
            line(testingPoints)
        case .training:

            // A dumbbell
            rounded(5, 6, 3, 12, 1)
            rounded(16, 6, 3, 12, 1)
            rounded(2, 9, 3, 6, 1)
            rounded(19, 9, 3, 6, 1)
            line([CGPoint(x: 8, y: 12), CGPoint(x: 16, y: 12)])
        case .progress:

            // A line along the bottom and a zigzag line going up
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

            // Two slider lines, each with a small circle on it
            line([CGPoint(x: 4, y: 7), CGPoint(x: 13, y: 7)])
            line([CGPoint(x: 17, y: 7), CGPoint(x: 20, y: 7)])
            line([CGPoint(x: 4, y: 17), CGPoint(x: 7, y: 17)])
            line([CGPoint(x: 11, y: 17), CGPoint(x: 20, y: 17)])
            circle(15, 7, 2)
            circle(9, 17, 2)
        }

        // Stretch the 24 by 24 drawing to fill the space
        return p.applying(CGAffineTransform(translationX: rect.minX, y: rect.minY).scaledBy(x: rect.width / 24, y: rect.height / 24))
    }
}


// An icon at a size and line thickness
struct IconView: View {

    // Which icon, how big it is, and how thick its lines are on the 24 point grid
    let icon: Icon
    var size: CGFloat = 24
    var weight: CGFloat = 2

    var body: some View {
        Group {

            // Fill the play triangle, and draw every other icon as rounded lines
            if icon == .play {
                IconShape(icon: icon).fill()
            } else {
                IconShape(icon: icon).stroke(style: StrokeStyle(lineWidth: weight * size / 24, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        // Screen readers skip the icon
        .accessibilityHidden(true)
    }
}


// THE SPIRAL ART

// Make the points of a spiral with a small wobble added, like one drawn by hand
func handDrawn(_ r1: Double, _ turns: Double, _ steps: Int) -> [[Double]] {
    spiralPoints(0, r1, turns, steps).enumerated().map { (i, pt) -> [Double] in

        // The point, how far along the spiral it is, and its angle
        let x: Double = pt[0], y: Double = pt[1]
        let p: Double = Double(i) / Double(steps)
        let th: Double = p * turns * 2 * Double.pi

        // Add up three slow waves and a fast jitter, growing in over the first fifth of the spiral
        let w1: Double = 0.6 * sin(th * 0.45 + 1.3), w2: Double = 0.3 * sin(th * 1.3 + 2.73), w3: Double = 0.1 * sin(th * 3.7 + 0.91)
        let wobble: Double = 4 * (w1 + w2 + w3)
        let dr: Double = (wobble + 0.4 * sin(Double(i) * 2.39996)) * min(1, p * 5)

        // Move the point out or in by that amount along its angle
        return [x + dr * cos(th), y + dr * sin(th)]
    }
}


// The spirals used in the logo and the pictures
enum Art {

    // The logo spiral, the gray guide spiral, and the hand drawn spiral
    static let mark = spiralPoints(0, 150, 2.25, 120)
    static let guide = spiralPoints(0, 150, 4, 720)
    static let trace = handDrawn(150, 4, 720)
}


// A line through spiral points, centered in a 340 by 340 box and stretched to fit
struct ArtShape: Shape {

    // The points to draw through
    let points: [[Double]]

    func path(in rect: CGRect) -> Path {
        var p = Path()

        // Move each point into the space and join them with lines
        for (i, pt) in points.enumerated() {
            let q = CGPoint(x: rect.minX + (170 + pt[0]) * rect.width / 340, y: rect.minY + (170 + pt[1]) * rect.height / 340)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        return p
    }
}


// The app's spiral logo
struct MarkView: View {

    // How big it is, its color or nil for the accent color, and the colors
    var size: CGFloat = 28
    var color: Color? = nil
    @Environment(\.palette) private var p

    var body: some View {

        // The logo spiral as a thick rounded line, skipped by screen readers
        ArtShape(points: Art.mark)
            .stroke(color ?? p.accent.color, style: StrokeStyle(lineWidth: 30 * size / 340, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}


// A small picture of the hand drawn spiral over the guide spiral
struct MiniArt: View {

    // How big it is, and the colors
    var size: CGFloat = 92
    @Environment(\.palette) private var p

    var body: some View {

        // The gray guide spiral with the accent colored hand drawn spiral on top
        ZStack {
            ArtShape(points: Art.guide).stroke(p.guide.color, lineWidth: 7 * size / 340)
            ArtShape(points: Art.trace).stroke(p.accent.color, style: StrokeStyle(lineWidth: 13 * size / 340, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size, height: size)
        // Screen readers skip the picture
        .accessibilityHidden(true)
    }
}


// THE TEXT STYLES

// The key that stores whether the screen is in collect mode, false to start
private struct CollectModeKey: EnvironmentKey {
    static let defaultValue = false
}


// Lets every view read and set collect mode
extension EnvironmentValues {

    // Whether the screen is in collect mode, which makes buttons and cards bigger
    var collectMode: Bool {
        get { self[CollectModeKey.self] }
        set { self[CollectModeKey.self] = newValue }
    }
}


// The kinds of text the screens use
enum TextKind {
    case body, lede, sub, strong, barTitle, sectionTitle, cardTitle, h3

    // A big headline with its size, line height and weight
    case h1(CGFloat, CGFloat, CGFloat)

    // The app name at a size
    case brand(CGFloat)
}


// Puts the font and color for a kind of text on a view
private struct TextKindModifier: ViewModifier {

    // The kind of text, and the colors
    let kind: TextKind
    @Environment(\.palette) private var p

    func body(content: Content) -> some View {

        // Pick the font and color for each kind
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

    // Put a kind of text on this view, like `.text(.body)`
    func text(_ kind: TextKind) -> some View { modifier(TextKindModifier(kind: kind)) }

    // Stretch this view to the full width, lined up on the left unless told otherwise
    func fullWidth(_ alignment: Alignment = .leading) -> some View { frame(maxWidth: .infinity, alignment: alignment) }
}


// THE BUTTONS

// The two kinds of button, filled or outlined
enum BtnKind {
    case primary, secondary
}


// The look of the app's buttons
struct NTButtonStyle: ButtonStyle {

    // The kind of button, and whether it is the small size
    var kind: BtnKind
    var compact = false

    // Build the button with NTButtonBody
    func makeBody(configuration: Configuration) -> some View {
        NTButtonBody(configuration: configuration, kind: kind, compact: compact)
    }
}


// What a button looks like, in each state
private struct NTButtonBody: View {

    // The button's label and press state, its kind, and whether it is the small size
    let configuration: ButtonStyleConfiguration
    let kind: BtnKind
    let compact: Bool

    // Whether the button can be tapped, the colors, and whether the screen is in collect mode
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.palette) private var p
    @Environment(\.collectMode) private var collect

    var body: some View {

        // True while the button is held down, unless it is turned off or Reduced Motion is on
        let pressed = configuration.isPressed && isEnabled && !Motion.reduced()

        // The label text, bigger in collect mode, in gray, white or the accent color
        configuration.label
            .nt(.body(collect && !compact ? 19 : 17, 600, lineHeight: 1.2))
            .multilineTextAlignment(.center)
            .foregroundStyle(!isEnabled ? p.ink2.color : kind == .primary ? Color.white : p.accent.color)
            // The size, full width unless compact, and taller in collect mode
            .padding(.horizontal, compact ? 20 : 24)
            .padding(.vertical, compact ? 0 : 8)
            .frame(maxWidth: compact ? nil : CGFloat.infinity, minHeight: compact ? 48 : (collect ? 64 : 56))
            // A gray fill when turned off, an accent fill for primary, and an accent outline for secondary
            .background(Capsule().fill(!isEnabled ? p.fill.color : kind == .primary ? p.accentFill.color : Color.clear))
            .overlay(Capsule().strokeBorder(isEnabled && kind == .secondary ? p.accent.color : Color.clear, lineWidth: 1.5))
            .contentShape(Capsule())
            // Shrink and fade a little while held down
            .scaleEffect(pressed ? 0.97 : 1)
            .opacity(pressed ? 0.8 : 1)
            .animation(Theme.ease(120), value: pressed)
    }
}


// A button with a title and an optional icon
struct Btn: View {

    // The title, the kind, the icon, whether it is the small size, and whether it is turned off
    let title: String
    var kind: BtnKind = .primary
    var icon: Icon? = nil
    var compact = false
    var disabled = false

    // What happens when it is tapped
    let action: () -> Void

    var body: some View {
        Button(action: action) {

            // The icon, if there is one, then the title
            HStack(spacing: 8) {
                if let icon { IconView(icon: icon, size: compact ? 16 : 22, weight: 2.2) }
                Text(title)
            }
        }
        .buttonStyle(NTButtonStyle(kind: kind, compact: compact))
        .disabled(disabled)
    }
}


// Two buttons side by side, or stacked when the row is too narrow for their words
struct ButtonPair<First: View, Second: View>: View {

    // The first and second buttons
    @ViewBuilder var first: () -> First
    @ViewBuilder var second: () -> Second

    var body: some View {

        // Use the side by side row if it fits, and the stack if it doesn't
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { first(); second() }
            VStack(spacing: 12) { first(); second() }
        }
    }
}


// A button look that shrinks and fades a little while held down
struct PressStyle: ButtonStyle {

    // How much to shrink, and whether to fade
    var scale: CGFloat = 0.97
    var dim = true

    // Shrink and fade the label while held down, unless Reduced Motion is on
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed && !Motion.reduced()
        return configuration.label
            .scaleEffect(pressed ? scale : 1)
            .opacity(pressed && dim ? 0.8 : 1)
            .animation(Theme.ease(120), value: pressed)
    }
}


// THE CARDS AND SMALL PIECES

// A rounded box with a thin border that holds other views in a column
struct Card<Content: View>: View {

    // The space inside the edges, the space between items, how items line up, and whether it fills the height
    var padding: CGFloat? = nil
    var spacing: CGFloat? = nil
    var alignment: HorizontalAlignment = .leading
    var fill = false

    // What goes inside the card
    @ViewBuilder var content: () -> Content

    // The colors, and whether the screen is in collect mode
    @Environment(\.palette) private var p
    @Environment(\.collectMode) private var collect

    var body: some View {

        // The items in a column, with more space in collect mode
        VStack(alignment: alignment, spacing: spacing ?? (collect ? 16 : 12)) { content() }
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: alignment == .center ? .top : .topLeading)
            .padding(padding ?? (collect ? 28 : 20))
            // The card color with a thin border around it
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(p.surface.color))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(p.line.color, lineWidth: p.hair))
    }
}


// A thin line across the full width
struct Hairline: View {

    // The colors
    @Environment(\.palette) private var p

    var body: some View {
        Rectangle().fill(p.line.color).frame(height: p.hair).frame(maxWidth: .infinity)
    }
}


// A small bold label in a gray rounded box
struct Pill: View {

    // The text to show, and the colors
    let text: Text
    @Environment(\.palette) private var p

    var body: some View {
        text.nt(.body(15, 600, lineHeight: 1.5))
            .foregroundStyle(p.ink.color)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(Capsule().fill(p.fill.color))
    }
}


// A lock icon next to the note that says the data stays on the device
struct LockNote: View {

    // The colors
    @Environment(\.palette) private var p

    var body: some View {

        // The lock icon, then the note, both in the softer text color
        HStack(alignment: .top, spacing: 10) {
            IconView(icon: .lock, size: 20).padding(.top, 1)
            Text(Copy.onDevice).nt(.body(15, lineHeight: 1.4))
        }
        .foregroundStyle(p.ink2.color)
    }
}


// THE TOP BAR PIECES

// A Back button with a left arrow
struct BackLink: View {

    // The words on the button, what happens when it is tapped, and the colors
    var label = "Back"
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {

            // The arrow and the words in the accent color, at least 44 points tall and wide
            HStack(spacing: 2) {
                IconView(icon: .back, size: 24, weight: 2.2)
                Text(label).nt(.body(17, lineHeight: 1.5))
            }
            .foregroundStyle(p.accent.color)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Move it 8 points to the left
        .padding(.leading, -8)
    }
}


// A text button for the top bar
struct BarLink: View {

    // The words, whether they are bold, what happens when it is tapped, and the colors
    let label: String
    var strong = false
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {

        // The words in the accent color, lined up on the right when bold and on the left when not
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


// A top bar with a left side, a middle and a right side
struct Bar<Left: View, Center: View, Right: View>: View {

    // How wide each side is
    var side: CGFloat = 88

    // What goes on the left, in the middle and on the right
    @ViewBuilder var left: () -> Left
    @ViewBuilder var center: () -> Center
    @ViewBuilder var right: () -> Right

    var body: some View {

        // The left side, the middle filling the rest, and the right side, at least 44 points tall
        HStack(spacing: 0) {
            left().frame(width: side, alignment: .leading)
            center().frame(maxWidth: .infinity).multilineTextAlignment(.center)
            right().frame(width: side, alignment: .trailing).multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
    }
}


// A row of short bars that shows how many steps are done
struct Segments: View {

    // How many steps there are, and the number of the step on now
    let total: Int
    let done: Int

    // The row's width, each bar's height, and the space between bars
    var width: CGFloat = 120
    var height: CGFloat = 5
    var gap: CGFloat = 6

    // Whether the newest bar grows in, and the colors
    var animateNow = true
    @Environment(\.palette) private var p

    var body: some View {
        HStack(spacing: gap) {
            ForEach(0..<total, id: \.self) { i in

                // Bars up to and including done are filled in the accent color, and the newest one can grow in
                if i <= done {
                    GrowBar(color: p.accent.color, height: height, grow: animateNow && i == done)
                } else {

                    // The rest are gray
                    Capsule().fill(p.fill.color).frame(height: height)
                }
            }
        }
        .frame(width: width)
        // Screen readers read the row as one item, like "2 of 5"
        .accessibilityElement()
        .accessibilityLabel("\(done) of \(total)")
    }
}


// One filled bar that can grow in from the left
private struct GrowBar: View {

    // The color, the height, and whether it grows in
    let color: Color
    let height: CGFloat
    let grow: Bool

    // Whether it has finished showing
    @State private var shown = false

    var body: some View {

        // The bar, squeezed to nothing from the left until shown
        Capsule().fill(color).frame(height: height)
            .scaleEffect(x: grow && !shown ? 0 : 1, y: 1, anchor: .leading)
            .onAppear {

                // Show it right away if it doesn't grow or Reduced Motion is on, and grow it in otherwise
                if !grow || Motion.reduced() { shown = true; return }
                withAnimation(Theme.ease(560)) { shown = true }
            }
    }
}


// THE CHOICES

// A rounded button for one choice, with a checkmark when picked
struct Chip: View {

    // The words, whether it is picked, what happens when it is tapped, and the colors
    let label: String
    let checked: Bool
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {

            // A checkmark that pops in when picked, then the words
            HStack(spacing: 6) {
                if checked {
                    IconView(icon: .checkmark, size: 17, weight: 3)
                        .transition(.scale(scale: 0).combined(with: .opacity))
                }
                Text(label)
            }
            // Bold words when picked
            .nt(.body(nil, checked ? 600 : 400, lineHeight: 1.2))
            .multilineTextAlignment(.center)
            .foregroundStyle(p.ink.color)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            // A pale accent fill and a thick accent border when picked, and the card color and a thin border when not
            .background(Capsule().fill(checked ? p.accentSoft.color : p.surface.color))
            .overlay(Capsule().strokeBorder(checked ? p.accent.color : p.line.color, lineWidth: checked ? 2 : p.hair))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        // Animate the change when picked or unpicked, unless Reduced Motion is on
        .animation(Motion.reduced() ? nil : Theme.ease(260), value: checked)
        // Screen readers say when it is picked
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}


// A grid of choice chips, two per row
struct ChipGrid: View {

    // The choices, the one picked now, and what happens when one is tapped
    let items: [(value: String, label: String)]
    let selected: String?
    let onSelect: (String) -> Void

    var body: some View {

        // Split the choices into rows of two
        let rows = stride(from: 0, to: items.count, by: 2).map { i in Array(items[i..<min(i + 2, items.count)]) }

        // Each row of chips, one under another
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


// A bold heading for a group of choices, with an optional value on the right
struct Legend: View {

    // The heading, the value on the right, and the colors
    let text: String
    var value: String? = nil
    @Environment(\.palette) private var p

    var body: some View {

        // The heading on the left and the value in the softer text color on the right
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text).text(.strong)
            Spacer(minLength: 0)
            if let value { Text(value).nt(.body()).foregroundStyle(p.ink2.color) }
        }
        // Screen readers read it as a heading
        .accessibilityAddTraits(.isHeader)
    }
}


// A row of options in a gray box, with a sliding knob behind the one picked
struct Segmented: View {

    // The options, the one picked now, and what happens when one is tapped, given where it was tapped
    let options: [(value: String, label: String)]
    let selected: String?
    let onSelect: (String, CGPoint) -> Void

    // The colors, and the space that lets the knob slide between options
    @Environment(\.palette) private var p
    @Namespace private var thumbSpace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<options.count, id: \.self) { i in

                // Whether this option is the one picked
                let on = options[i].value == selected

                // The option's words, bold when picked
                Text(options[i].label)
                    .nt(.body(16, on ? 600 : 400, lineHeight: 1.2))
                    .foregroundStyle(p.ink.color)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    // The knob with a soft shadow behind the picked option
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(p.segThumb.color)
                                .shadow(color: .black.opacity(0.16), radius: 3, x: 0, y: 2)
                                .matchedGeometryEffect(id: "thumb", in: thumbSpace)
                        }
                    }
                    .contentShape(Rectangle())
                    // Pick the option when tapped, passing where on the screen it was tapped
                    .onTapGesture(coordinateSpace: .global) { location in onSelect(options[i].value, location) }
                    // Screen readers read it as a button, say when it is picked, and can pick it
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
                    .accessibilityAction { onSelect(options[i].value, .zero) }
            }
        }
        // The gray box around the options
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.fill.color))
        // Slide the knob when the choice changes, unless Reduced Motion is on
        .animation(Motion.reduced() ? nil : Theme.ease(300), value: selected)
        .padding(.top, 12)
    }
}


// A rounded square box that shows a checkmark when checked
struct CheckBox: View {

    // Whether it is checked, and the colors
    let checked: Bool
    @Environment(\.palette) private var p

    var body: some View {
        ZStack {

            // The box, filled with the accent fill color when checked
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(checked ? p.accentFill.color : p.surface.color)

            // The border, in the accent fill color when checked and gray when not
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(checked ? p.accentFill.color : p.ink2.color.opacity(0.6), lineWidth: 2)

            // A white checkmark when checked
            if checked {
                IconView(icon: .checkmark, size: 20, weight: 3).foregroundStyle(Color.white)
            }
        }
        .frame(width: 26, height: 26)
        // A little smaller when not checked, animated unless Reduced Motion is on
        .scaleEffect(checked ? 1 : 0.94)
        .animation(Motion.reduced() ? nil : Theme.ease(260), value: checked)
    }
}


// A tappable row with a check box and text
struct CheckRow: View {

    // The text, and a smaller line under it inside the same tap target
    let text: String
    var detail: String? = nil

    // Whether it is checked, whether it is the small size, and what happens when it is tapped
    let checked: Bool
    var compact = false
    let action: () -> Void

    // The colors
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(alignment: detail == nil ? .center : .top, spacing: 16) {

                // The check box
                CheckBox(checked: checked)

                // The text, and the smaller line under it if there is one
                VStack(alignment: .leading, spacing: 4) {
                    Text(text).nt(.body(nil, lineHeight: 1.35)).foregroundStyle(p.ink.color).multilineTextAlignment(.leading)
                    if let detail, !detail.isEmpty {
                        Text(detail).text(.sub).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            // At least 72 points tall with space around it, unless it is the small size
            .frame(minHeight: compact ? 0 : 72)
            .padding(.vertical, compact ? 0 : 14)
            .padding(.horizontal, compact ? 0 : 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Screen readers say when it is checked
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}


// THE STATUS MESSAGE

// Shakes a view left and right
@MainActor
@Observable
final class Shaker {

    // How far left or right the view is moved now
    var x: CGFloat = 0

    // The id of the waiting screen refresh callback
    @ObservationIgnored private var frame = 0

    // Shake the view for 440 milliseconds, unless Reduced Motion is on
    func shake() {
        if Motion.reduced() { return }

        // Stop any shake already running and note the start time
        Frames.cancel(frame)
        let start = Frames.now()

        // On each screen refresh, move left and right by smaller amounts until the time is up
        func step(_ now: Double) {
            let u = min(1, (now - start) / 440)
            x = u >= 1 ? 0 : CGFloat(CubicBezier.keyframes(u, [(0, 0), (0.2, -7), (0.4, 6), (0.6, -3), (0.8, 2), (0.9999, 0)], .brand))
            if u < 1 { frame = Frames.next(step) }
        }
        frame = Frames.next(step)
    }
}


// A card with an info icon and a message, with the first sentence in bold
struct StatusBox: View {

    // The message, or nil to show nothing, and how far it is shaken
    let sentence: String?
    let shake: CGFloat

    // The colors and text sizes
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        if let sentence {

            // The spot just after the first period
            let cut = sentence.firstIndex(of: ".").map { sentence.index(after: $0) } ?? sentence.startIndex
            Card(padding: 0) {
                HStack(alignment: .top, spacing: 12) {

                    // The info icon in the accent color
                    IconView(icon: .info, size: 22).foregroundStyle(p.accent.color)

                    // The first sentence in bold followed by the rest in normal weight
                    (ntText(String(sentence[..<cut]), .body(15, 600, lineHeight: 1.4), typo) + ntText(String(sentence[cut...]), .body(15, lineHeight: 1.4), typo))
                        .lineSpacing(lineGap(.body(15, lineHeight: 1.4), typo))
                        .foregroundStyle(p.ink.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
            }
            // Move it left and right by the shake amount
            .offset(x: shake)
            .padding(.top, 16)
            // Screen readers read the card as one item
            .accessibilityElement(children: .combine)
        }
    }
}


// THE SCREEN TITLES

// A screen title's words and where its top and bottom are on the screen
struct TitleFrame: Equatable {
    var text: String
    var minY: CGFloat
    var maxY: CGFloat
}


// Passes the screen title's place up to the screen, keeping the first one found
struct TitleKey: PreferenceKey {
    static let defaultValue: TitleFrame? = nil
    static func reduce(value: inout TitleFrame?, nextValue: () -> TitleFrame?) {
        value = value ?? nextValue()
    }
}


// A big headline used as a screen's title
struct H1: View {

    // The words, size, line height, space above, and weight
    let text: String
    var size: CGFloat = 34
    var lineHeight: CGFloat = 1.1
    var top: CGFloat = 16
    var weight: CGFloat = 500

    var body: some View {

        // The headline, read as a heading by screen readers and marked as the screen's title
        Text(text)
            .text(.h1(size, lineHeight, weight))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, top)
            .accessibilityAddTraits(.isHeader)
            .screenTitle(text)
    }
}


extension View {

    // Mark this as the screen's title by passing its words and place on the screen up to the screen
    func screenTitle(_ text: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: TitleKey.self, value: TitleFrame(text: text, minY: geo.frame(in: .global).minY, maxY: geo.frame(in: .global).maxY))
        })
    }
}


// THE SCREEN FRAME

// A scrolling screen that keeps its content clear of the edges and the tab bar
struct ScreenView<Content: View>: View {

    // The widest the content can be, whether the screen has the tab bar, whether it reports its title, and the space at the top
    var maxWidth: CGFloat = 560
    var tabbed = false
    var titled = false
    var padTop: CGFloat? = nil

    // What goes on the screen, given a proxy that can scroll to a spot
    @ViewBuilder var content: (ScrollViewProxy) -> Content

    // The app model and text sizes
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo

    var body: some View {
        GeometryReader { geo in

            // The space taken by the status bar, the home indicator and the screen edges
            let insets = geo.safeAreaInsets

            // True when the tab bar is along the top
            let barOnTop = tabbed && typo.tabsOnTop
            ScrollViewReader { proxy in
                ScrollView(.vertical) {

                    // The content in a column
                    VStack(alignment: .leading, spacing: 0) { content(proxy) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Space at the top, below the tab bar when it is on top
                        .padding(.top, padTop ?? (barOnTop ? insets.top + TabBar.topHeight + 16 : max(insets.top, 24)))
                        // At least 24 points on each side
                        .padding(.leading, max(insets.leading, 24))
                        .padding(.trailing, max(insets.trailing, 24))
                        // Space at the bottom, above the tab bar when it is on the bottom
                        .padding(.bottom, tabbed && !barOnTop ? max(insets.bottom, 8) + 104 : max(insets.bottom, 24))
                        // Keep the content no wider than maxWidth, centered, and at least as tall as the screen
                        .frame(maxWidth: maxWidth)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height + insets.top + insets.bottom, alignment: .top)
                }
                .scrollIndicators(.hidden)
            }
            .ignoresSafeArea(.container)
        }
        // Tell the app model where the title is, or nil if this screen doesn't report one
        .onPreferenceChange(TitleKey.self) { value in
            MainActor.assumeIsolated {
                app.titleChanged(titled ? value : nil)
            }
        }
    }
}


// THE TAB BAR

// The tab bar, along the top on an iPad and along the bottom on a phone
struct TabBar: View {

    // Whether it goes along the top
    var top: Bool

    // The status bar above a top bar, or the home indicator below a bottom bar
    var inset: CGFloat

    // The app model, colors and text sizes, and the space that lets the highlight slide between tabs
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo
    @Namespace private var lensSpace

    // How tall the top bar is under the status bar
    static let topHeight: CGFloat = 64

    // Every tab, with its screen, its name and its icon
    static let items: [(id: Screen, label: String, icon: Icon)] = [
        (.dashboard, "Dashboard", .dashboard),
        (.testing, "Testing", .testing),
        (.training, "Training", .training),
        (.progress, "Progress", .progress),
        (.care, "Care", .care),
        (.settings, "Settings", .settings),
    ]

    var body: some View {
        if top { topBar } else { bottomBar }
    }

    // The top bar with Dashboard first and bigger, then the middle tabs, then Settings as an icon at the end
    private var topBar: some View {

        // The tabs other than Dashboard and Settings
        let middle = Self.items.filter { item in item.id != .dashboard && item.id != .settings }

        // Show the middle tabs' names only when the window is at least 760 points wide
        let labeled = typo.width >= 760
        return HStack(spacing: 12) {

            // The Dashboard tab
            homeTab
            Spacer(minLength: 0)

            // The middle tabs
            HStack(spacing: 4) {
                ForEach(middle, id: \.id) { item in pill(item, labeled: labeled) }
            }
            Spacer(minLength: 0)

            // The Settings tab as an icon only
            pill(Self.items[Self.items.count - 1], labeled: false)
        }
        // Sit below the status bar, in the card color, with a thin line along the bottom
        .padding(.horizontal, 20)
        .padding(.top, inset)
        .frame(height: inset + Self.topHeight)
        .frame(maxWidth: .infinity)
        .background(p.surface.color)
        .overlay(alignment: .bottom) { Hairline() }
    }

    // The Dashboard tab in the top bar, with the mascot and the word Dashboard
    private var homeTab: some View {

        // Whether the dashboard is the screen showing now
        let current = app.screen == .dashboard
        return Button {
            app.go(.dashboard)
        } label: {

            // The mascot and the word Dashboard
            HStack(spacing: 10) {
                Mascot(mood: "idle").frame(width: 32, height: 32)
                Text("Dashboard").nt(.body(21, 600, lineHeight: 1)).lineLimit(1)
            }
            // The accent color when showing, and the main text color when not
            .foregroundStyle(current ? p.accent.color : p.ink.color)
            .padding(.leading, 8)
            .padding(.trailing, 18)
            .frame(minHeight: 48)
            // The pale accent highlight behind it when showing
            .background {
                if current { Capsule().fill(p.accentSoft.color).matchedGeometryEffect(id: "lens", in: lensSpace) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.95, dim: false))
        // Screen readers read it as Dashboard and say when it is showing
        .accessibilityLabel("Dashboard")
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }

    // One tab in the top bar, with its icon and, when labeled, its name
    private func pill(_ item: (id: Screen, label: String, icon: Icon), labeled: Bool) -> some View {

        // Whether this tab's screen is the one showing now
        let current = app.screen == item.id
        return Button {
            app.go(item.id)
        } label: {

            // The icon, and the name when labeled
            HStack(spacing: 8) {
                IconView(icon: item.icon, size: 22)
                if labeled { Text(item.label).nt(.body(16, 600, lineHeight: 1)).lineLimit(1) }
            }
            // The accent color when showing, and the softer text color when not
            .foregroundStyle(current ? p.accent.color : p.ink2.color)
            .padding(.horizontal, labeled ? 14 : 11)
            .frame(minWidth: 44, minHeight: 44)
            // The pale accent highlight behind it when showing
            .background {
                if current { Capsule().fill(p.accentSoft.color).matchedGeometryEffect(id: "lens", in: lensSpace) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(scale: 0.95, dim: false))
        // Screen readers read the tab's name and say when it is showing
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(current ? [.isSelected] : [])
    }

    // The bottom bar with every tab except Settings
    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(Self.items.filter { item in item.id != .settings }, id: \.id) { item in

                // Whether this tab's screen is the one showing now
                let current = app.screen == item.id
                Button {
                    app.go(item.id)
                } label: {

                    // The icon over the name
                    VStack(spacing: 6) {
                        IconView(icon: item.icon, size: 24)
                        Text(item.label).nt(.body(15, 600, lineHeight: 1)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    // The accent color when showing, and the softer text color when not
                    .foregroundStyle(current ? p.accent.color : p.ink2.color)
                    // At most 160 points wide on screens at least 700 points wide
                    .frame(maxWidth: typo.width >= 700 ? CGFloat(160) : CGFloat.infinity, minHeight: 58)
                    // The pale accent highlight behind the icon when showing
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
                // Screen readers say when the tab is showing
                .accessibilityAddTraits(current ? [.isSelected] : [])
            }
        }
        // Sit above the home indicator, in the card color, with a thin line along the top
        .padding(.top, 6)
        .padding(.horizontal, 12)
        .padding(.bottom, max(inset, 8))
        .frame(maxWidth: .infinity)
        .background(p.surface.color)
        .overlay(alignment: .top) { Hairline() }
    }
}


// THE OVERLAYS

// The small title bar that slides down from the top
struct CompactBar: View {

    // The space taken by the status bar, the app model, and the colors
    var topInset: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {

        // Whether the bar is showing
        let shown = app.compactShown

        // The screen's title in bold on one line, cut off with "…" if too long
        Text(app.compactTitle)
            .nt(.body(nil, 600, lineHeight: 1.3))
            .foregroundStyle(p.ink.color)
            .lineLimit(1)
            .truncationMode(.tail)
            // Space around the title, below the status bar
            .padding(.horizontal, 64)
            .padding(.top, max(topInset, 10))
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .bottom)
            // The background color with a thin line along the bottom
            .background(p.bg.color)
            .overlay(alignment: .bottom) { Hairline() }
            // Slide up out of sight and fade out when not showing, animated unless Reduced Motion is on
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : -(max(topInset, 10) + 44))
            .animation(Motion.reduced() ? nil : Theme.ease(380), value: shown)
            // Taps go through it, and screen readers skip it
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}


// The short message that pops up near the bottom of the screen
struct ToastView: View {

    // The space taken by the home indicator, the app model, and the colors
    var bottomInset: CGFloat
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    // How much of the checkmark has been drawn, from 0 to 1
    @State private var drawn: CGFloat = 0

    var body: some View {

        // Whether the message is showing
        let shown = app.toastShown
        HStack(spacing: 8) {

            // A checkmark that draws itself in for a success, and an info icon otherwise
            if app.toastOK {
                IconShape(icon: .checkmark)
                    .trim(from: 0, to: drawn)
                    .stroke(style: StrokeStyle(lineWidth: 2.6 * 20 / 24, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
            } else {
                IconView(icon: .info, size: 20, weight: 2.2)
            }

            // The message
            Text(app.toastText).nt(.body(15, 600, lineHeight: 1.3))
        }
        // Light text on a dark rounded box with a shadow, or the other way around in dark mode
        .foregroundStyle(p.bg.color)
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 18)
        .background(Capsule().fill(p.ink.color))
        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
        // Fade out when hidden, and also shrink and drop down unless Reduced Motion is on
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown || Motion.reduced() ? 1 : 0.96)
        .offset(y: shown || Motion.reduced() ? 0 : 16)
        // Sit 88 points above the home indicator
        .padding(.bottom, max(bottomInset, 8) + 88)
        // Taps go through it, and screen readers read it as one item
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        // Draw the checkmark in again each time a new message shows
        .onChange(of: app.toastID) { _, _ in
            drawn = 0

            // With Reduced Motion on, show the whole checkmark right away
            if Motion.reduced() {
                drawn = 1
                return
            }

            // Otherwise draw it in after a short pause
            withAnimation(Theme.ease(380).delay(0.14)) { drawn = 1 }
        }
    }
}


// The full screen that shows while a drawing is being measured
struct MeasuringOverlay: View {

    // The app model and the colors
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {

        // Whether the screen is showing
        let shown = app.measuringShown
        ZStack {

            // The background color over the whole screen
            p.bg.color.ignoresSafeArea()
            VStack(spacing: 14) {

                // The thinking mascot and the title
                Mascot(mood: "thinking").frame(width: 120, height: 120)
                Text(Copy.measuring).nt(.body(24, 600, lineHeight: 1.3)).foregroundStyle(p.ink.color)

                // One row per step in Copy.measureSteps
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<Copy.measureSteps.count, id: \.self) { i in

                        // Whether this step is done
                        let on = i < app.measuringOn
                        HStack(spacing: 12) {

                            // A filled circle with a checkmark when done, and an empty circle when not
                            ZStack {
                                if on {
                                    Circle().fill(p.accent.color)
                                    IconView(icon: .checkmark, size: 15, weight: 3).foregroundStyle(Color.white)
                                } else {
                                    Circle().strokeBorder(p.guide.color, lineWidth: 2)
                                }
                            }
                            .frame(width: 24, height: 24)

                            // The step's words
                            Text(Copy.measureSteps[i]).nt(.body()).foregroundStyle(on ? p.ink.color : p.ink2.color)
                        }
                        // Faded until done
                        .opacity(on ? 1 : 0.45)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .frame(maxWidth: 360)
            // Slightly lower and smaller when not showing
            .offset(y: shown ? 0 : 14)
            .scaleEffect(shown ? 1 : 0.97)
            .padding(24)
        }
        // Fade out when not showing, and screen readers read it as one item
        .opacity(shown ? 1 : 0)
        .accessibilityElement(children: .combine)
    }
}


// THE TRACK

// A gray track with a center mark and dots placed along it
struct Track: View {

    // The dots, each with its place from 0 to 1 and whether it is an earlier result, and whether to place them now
    let dots: [(frac: Double, then: Bool)]
    var active = true

    // The colors, and whether the dots have moved to their places
    @Environment(\.palette) private var p
    @State private var settled = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {

                // The gray track and the mark in the middle
                RoundedRectangle(cornerRadius: 2).fill(p.fill.color).frame(width: w, height: 4).offset(y: 8)
                RoundedRectangle(cornerRadius: 1).fill(p.guide.color).frame(width: 2, height: 14).offset(x: w / 2 - 1, y: 3)

                // Each dot
                ForEach(0..<dots.count, id: \.self) { i in

                    // Its place, rounded and kept between 0.03 and 0.97, or the middle before settling
                    let d = dots[i]
                    let at = settled ? min(max(jsRound(d.frac * 100) / 100, 0.03), 0.97) : 0.5

                    // A hollow ring for an earlier result, and a filled dot otherwise
                    ZStack {
                        if d.then {
                            Circle().fill(p.surface.color)
                            Circle().strokeBorder(p.accent.color, lineWidth: 3)
                        } else {
                            Circle().fill(p.accent.color)
                        }
                    }
                    .frame(width: 20, height: 20)
                    // A ring of the card color around the dot
                    .background(Circle().fill(p.surface.color).padding(-3))
                    // Move it to its place, and hide it until settled
                    .offset(x: w * CGFloat(at) - 10)
                    .opacity(settled ? 1 : 0)
                }
            }
        }
        .frame(height: 20)
        .padding(.horizontal, 8)
        .padding(.top, 6)
        // Screen readers skip the track
        .accessibilityHidden(true)
        // Place the dots when it shows or when it becomes active
        .onAppear { if active { settle() } }
        .onChange(of: active) { _, now in if now { settle() } }
    }

    // Move the dots to their places once
    private func settle() {
        if settled { return }

        // With Reduced Motion on, place them right away
        if Motion.reduced() {
            settled = true
            return
        }

        // Otherwise slide them out from the middle
        withAnimation(Theme.ease(640)) { settled = true }
    }
}


// THE SCROLL IN ANIMATION

// Fades a view in and slides it up once it scrolls onto the screen
struct Reveal: ViewModifier {

    // The view's place in its list, and what to run once it shows
    let index: Int
    var onIn: (@MainActor () -> Void)? = nil

    // Whether it has shown, and the text sizes
    @State private var shown = false
    @Environment(\.typo) private var typo

    func body(content: Content) -> some View {

        // Hidden and 14 points lower until shown
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            // Check the view's place on the screen when it appears and each time it moves
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { check(geo.frame(in: .global)) }
                    .onChange(of: geo.frame(in: .global).minY) { _, _ in check(geo.frame(in: .global)) }
            })
    }

    // Show the view if it is on the screen
    private func check(_ frame: CGRect) {
        if shown { return }

        // With Reduced Motion on, show it right away
        if Motion.reduced() {
            shown = true
            onIn?()
            return
        }

        // Once its top is above 94 percent of the screen height and its bottom is below the top, animate it in after a delay that grows with its place in the list
        if frame.minY < typo.height * 0.94 && frame.maxY > 0 {
            withAnimation(Theme.ease(600).delay(Double(index % 6) * 0.07)) { shown = true }
            onIn?()
        }
    }
}


extension View {

    // Fade this view in and slide it up once it scrolls onto the screen, like `.reveal(0)`
    func reveal(_ index: Int, onIn: (@MainActor () -> Void)? = nil) -> some View { modifier(Reveal(index: index, onIn: onIn)) }
}


// THE TEXT HELPERS

// Make a piece of text in a text style at the reader's text size
func ntText(_ string: String, _ font: NTFont, _ typo: Typography) -> Text {
    Text(string).font(Font(Fonts.make(font, size: typo.scaled(font.size ?? typo.body)) as CTFont))
}

// The extra space between lines needed for a text style's line height
func lineGap(_ font: NTFont, _ typo: Typography) -> CGFloat {
    let size = typo.scaled(font.size ?? typo.body)
    return max(0, size * font.lineHeight - Fonts.make(font, size: size).lineHeight)
}
