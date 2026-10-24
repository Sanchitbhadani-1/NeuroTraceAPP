import SwiftUI
import UIKit

// Define the set amount of turns in a spiral
private let turns = 4.0

// Create the list of points
func spiralPoints(_ r0: Double, _ r1: Double, _ turns: Double, _ steps: Int) -> [[Double]] {
    var pts: [[Double]] = []
    for step in 0...steps {
        let progress = Double(step) / Double(steps) // How far along the spiral this point is, from 0 to 1
        let theta = progress * turns * 2 * Double.pi
        let r = r0 + progress * (r1 - r0) // The distance from the center grows linearly from r0 to r1
        
        pts.append([r * cos(theta), r * sin(theta)]) // Turn the angle and distance into an x and y point
    }
    return pts
}

// The three ways someone can draw. The raw values get saved with every drawing, so they must not change
enum InputKind: String {
    case pencil, touch, mouse

    // Work out if a touch came from the Apple Pencil, a mouse or trackpad, or a finger
    @MainActor init(_ touch: UITouch) {
        switch touch.type {
        case .pencil: self = .pencil
        case .indirectPointer, .indirect: self = .mouse
        default: self = .touch
        }
    }
}

// Name the device the drawing was made on, so it gets saved with the drawing
@MainActor private func deviceLabel() -> String {
    if UIDevice.current.userInterfaceIdiom == .pad { return "iPad" }
    if UIDevice.current.userInterfaceIdiom == .phone { return "iPhone" }
    return UIDevice.current.model.isEmpty ? "unknown" : UIDevice.current.model
}

// A short name for any function that draws onto the pad, given the canvas, its width and its height
typealias PadDraw = @MainActor (CGContext, CGFloat, CGFloat) -> Void

// Draw the gray guide spiral in the middle of the pad
@MainActor private func spiralGuide(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
    // Gray line that gets thicker on bigger pads, but never thinner than 2
    ctx.setStrokeColor(Palette.current.guide.ui.cgColor)
    ctx.setLineWidth(max(2, w / 180))
    ctx.beginPath()
    // Make the spiral as big as the pad allows, with 20 points of space at the edge
    let maxR = min(w, h) / 2 - 20
    var first = true
    for pt in spiralPoints(0, Double(maxR), turns, 1000) {
        // Move each point so the spiral sits in the middle of the pad
        let point = CGPoint(x: w / 2 + pt[0], y: h / 2 + pt[1])
        // Start the line at the first point, then connect the rest
        if first { ctx.move(to: point); first = false } else { ctx.addLine(to: point) }
    }
    ctx.strokePath()
}

// The see through layer that everything on the pad gets drawn on
private final class PadCanvas: UIView {
    // The function that does the drawing, handed in by the pad
    var paint: (@MainActor (CGContext) -> Void)?

    // Clear background, redraw when the size changes, and let touches pass through to the pad
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
    }

    // UIKit requires this, but the app never uses it
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // UIKit calls this when it's time to draw. Grab the canvas and hand it to paint
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        paint?(ctx)
    }
}

// Make a pad. It uses the spiral guide unless a screen passes in its own, like the exercises do
@MainActor
func createPad(onInk: @escaping @MainActor (String?) -> Void, guide: PadDraw? = nil, overlay: PadDraw? = nil) -> Pad {
    Pad(onInk: onInk, guide: guide ?? spiralGuide, overlay: overlay)
}

// The drawing area. It records every touch as a sample and draws the line
final class Pad: UIView {
    // Runs when a new stroke starts, or with "resize" when a size change wipes the drawing
    var onInk: @MainActor (String?) -> Void
    // Draws the guide behind the ink
    var guide: PadDraw
    // Extra drawing on top of everything, if a screen wants it
    var overlay: PadDraw?
    // Lets the screen hear about every touch, used for the pen tip
    var onPointer: ((UITouch, UITouch.Phase) -> Void)?

    // The pulsing circle around the start dot
    private let halo = UIView(frame: CGRect(x: 0, y: 0, width: 36, height: 36))
    // The layer the pad draws onto
    private let canvas = PadCanvas(frame: .zero)

    // The pad's size, saved so it can tell when the size changes
    private var w: CGFloat = 0, h: CGFloat = 0
    // Every recorded point of the drawing
    private var samples: [Sample] = []
    // Where each stroke begins in samples
    private var starts: [Int] = []
    // The time of the first sample, so the drawing's times start at 0
    private var t0: Double = 0
    // Pencil, touch or mouse, decided by the first stroke
    private var inputKind: InputKind? = nil
    // True once the Apple Pencil has touched the pad
    private var pencilSeen = false
    // The touch that is drawing right now
    private var active: UITouch? = nil
    // Whether the start dot is showing
    private var dot = false
    // Every touch on the screen right now and what kind it is
    private var down: [ObjectIdentifier: UITouch.TouchType] = [:]

    init(onInk: @escaping @MainActor (String?) -> Void, guide: @escaping PadDraw, overlay: PadDraw?) {
        // Save what the screen passed in
        self.onInk = onInk
        self.guide = guide
        self.overlay = overlay
        super.init(frame: .zero)
        // Hear about every finger on the screen, so the extra ones can be ignored
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        // Make the halo a faded circle that stays hidden until the start dot shows
        halo.layer.cornerRadius = 18
        halo.isUserInteractionEnabled = false
        halo.isHidden = true
        halo.alpha = 0.35
        halo.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
        // The halo goes in first so the canvas draws over it
        addSubview(halo)
        addSubview(canvas)
        // Render draws the canvas. Weak self stops the two from keeping each other alive forever
        canvas.paint = { [weak self] ctx in self?.render(ctx) }
        // Let VoiceOver users find the pad and draw on it
        isAccessibilityElement = true
        accessibilityTraits = [.image, .allowsDirectInteraction]
        accessibilityLabel = "Drawing area with the spiral guide"
        // Redraw in the new colors whenever the theme changes
        NotificationCenter.default.addObserver(self, selector: #selector(paletteChanged), name: .paletteChanged, object: nil)
    }

    // UIKit requires this, but the app never uses it
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Don't let a drag on the pad turn into scrolling the screen
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        !(gestureRecognizer is UIPanGestureRecognizer)
    }

    // When the theme changes, recolor the halo and redraw
    @objc private func paletteChanged() {
        halo.backgroundColor = Palette.current.accent.ui
        draw()
    }

    // Draw the whole pad from back to front
    private func render(_ ctx: CGContext) {
        // Nothing to draw until the pad has a size
        if w == 0 { return }
        // Wipe what was drawn last time
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        // Guide first so the ink goes on top of it
        guide(ctx, w, h)

        // The start dot in the middle, in the accent color
        if dot {
            ctx.setFillColor(Palette.current.accent.ui.cgColor)
            ctx.beginPath()
            ctx.addArc(center: CGPoint(x: w / 2, y: h / 2), radius: 7.5, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.fillPath()
        }

        // Draw each stroke, from where it starts to where the next one starts
        for (i, start) in starts.enumerated() { ink(ctx, start, i + 1 < starts.count ? starts[i + 1] : samples.count) }
        // Anything extra goes on top of everything else
        overlay?(ctx, w, h)
    }

    // Draw one stroke of ink
    private func ink(_ ctx: CGContext, _ from: Int, _ to: Int) {
        // Start at the stroke's first point, or one before it so the line stays connected
        let first = starts.contains(from) ? from : from - 1
        // The line in the accent color, with round ends, thicker on bigger pads
        ctx.setStrokeColor(Palette.current.accent.ui.cgColor)
        ctx.setLineWidth(max(3, w / 110))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.beginPath()
        // Connect every point in order
        ctx.move(to: CGPoint(x: samples[first].x, y: samples[first].y))
        for i in first..<to { ctx.addLine(to: CGPoint(x: samples[i].x, y: samples[i].y)) }
        ctx.strokePath()
    }

    // Ask UIKit to redraw the canvas on the next screen update
    private func draw() { canvas.setNeedsDisplay() }

    // UIKit calls this whenever the pad's size or position changes
    override func layoutSubviews() {
        super.layoutSubviews()
        // Make the canvas fill the pad and keep the halo in the middle
        canvas.frame = bounds
        halo.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let width = bounds.width, height = bounds.height
        // Wait until the pad has a real size
        if width == 0 || height == 0 { return }
        // If the size changed after drawing started, the old points no longer line up, so clear them
        let cleared = (width != w || height != h) && samples.count > 0
        if cleared { reset() }
        // Save the new size and redraw
        w = width
        h = height
        halo.backgroundColor = Palette.current.accent.ui
        draw()
        // Tell the screen so it can ask for the spiral again
        if cleared { onInk("resize") }
    }

    // Turn touch events into samples and save them
    private func addSamples(_ events: [UITouch]) {
        for ev in events {
            // The time of this event in milliseconds
            let stamp = ev.timestamp * 1000
            // Remember when the drawing started
            if samples.isEmpty { t0 = stamp }
            // The most exact position UIKit can give
            let point = ev.preciseLocation(in: self)
            // Pencil only. How far it leans sideways and forward in degrees, saved the way the web version did
            var tiltX = 0.0, tiltY = 0.0
            if ev.type == .pencil {
                let altitude = Double(ev.altitudeAngle), azimuth = Double(ev.azimuthAngle(in: self))
                // Standing straight up means no lean, so skip the math
                if altitude < Double.pi / 2 {
                    let tanAlt = tan(altitude)
                    tiltX = jsRound(atan(cos(azimuth) / tanAlt) * 180 / Double.pi)
                    tiltY = jsRound(atan(sin(azimuth) / tanAlt) * 180 / Double.pi)
                }
            }
            // Time is in seconds since the first sample. Pressure goes from 0 to 1, or 0 for a finger
            samples.append(Sample(
                t: (stamp - t0) / 1000,
                x: Double(point.x),
                y: Double(point.y),
                pressure: ev.maximumPossibleForce > 0 ? Double(ev.force / ev.maximumPossibleForce) : 0,
                // Never save a broken tilt value
                tiltX: tiltX.isNaN ? 0 : tiltX,
                tiltY: tiltY.isNaN ? 0 : tiltY
            ))
        }
        // Show the new ink
        draw()
    }

    // Runs when a finger, Pencil or mouse first touches the pad
    private func strokeBegan(_ ev: UITouch, _ event: UIEvent?, isPrimary: Bool) {
        let kind = InputKind(ev)
        // If the Pencil shows up after a finger started drawing, throw out the finger drawing
        if kind == .pencil {
            if !pencilSeen && inputKind == .touch { reset() }
            pencilSeen = true
        }
        // A right click counts as button 2
        let button = ev.type == .indirectPointer && event?.buttonMask == .secondary ? 2 : 0
        // Ignore extra fingers, right clicks, and new touches while one is already drawing
        if !isPrimary || button != 0 || active != nil { return }
        // Once the Pencil has been used, ignore fingers so a resting palm can't draw
        if kind == .touch && pencilSeen { return }
        // This touch is now the one drawing
        active = ev
        // Hide the start dot once drawing begins
        if dot { showStartDot(false) }
        // The first stroke decides the input type
        if samples.isEmpty { inputKind = kind }
        // Mark where this stroke starts, save its first point, and tell the screen drawing started
        starts.append(samples.count)
        addSamples([ev])
        onInk(nil)
    }

    // UIKit calls this when touches land on the pad
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            // It's the main touch if nothing of the same kind is already down
            let isPrimary = !down.values.contains(touch.type)
            // Remember this touch until it lifts
            down[ObjectIdentifier(touch)] = touch.type
            strokeBegan(touch, event, isPrimary: isPrimary)
            onPointer?(touch, .began)
        }
    }

    // UIKit calls this as touches move
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            onPointer?(touch, .moved)
            // Only the touch that's drawing gets recorded
            if touch !== active { continue }
            // Get every sample since the last screen update, not just the newest one
            let batch = event?.coalescedTouches(for: touch) ?? []
            addSamples(batch.isEmpty ? [touch] : batch)
        }
    }

    // When touches lift or get canceled, forget them
    private func end(_ touches: Set<UITouch>, _ phase: UITouch.Phase) {
        for touch in touches {
            down[ObjectIdentifier(touch)] = nil
            // If it was the drawing touch, that stroke is over
            if touch === active { active = nil }
            onPointer?(touch, phase)
        }
    }

    // Lifting and canceling are handled the same way
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, .ended) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, .cancelled) }

    // Clear the drawing and start fresh
    func reset() {
        samples = []
        starts = []
        inputKind = nil
        pencilSeen = false
        active = nil
        draw()
    }

    // Show or hide the start dot and its pulsing halo
    func showStartDot(_ on: Bool) {
        dot = on
        halo.isHidden = !on
        // Stop any old pulse first
        halo.layer.removeAllAnimations()
        // Pulse the halo, unless reduced motion is on
        if on && !Motion.reduced() {
            // Grow from 70% to 125% of its size
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.7
            scale.toValue = 1.25
            // Fade out as it grows
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.35
            fade.toValue = 0.12
            // Play both together, growing and shrinking forever
            let pulse = CAAnimationGroup()
            pulse.animations = [scale, fade]
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            halo.layer.add(pulse, forKey: "pulse")
        }
        draw()
    }

    // Let other code ask for a redraw
    func redraw() { draw() }
    // When the drawing started, or nil if nothing is drawn yet
    func startedAt() -> Double? { samples.count > 0 ? t0 : nil }
    // Whether anything has been drawn
    func hasInk() -> Bool { samples.count > 0 }
    // Where each stroke starts
    func strokeStarts() -> [Int] { starts }
    // Package the drawing into a Trace so it can be measured and saved
    func trace(_ hand: String? = nil) -> Trace {
        Trace(task: "spiral", hand: hand, inputType: inputKind?.rawValue, deviceLabel: deviceLabel(), samples: samples)
    }
}

// Put the UIKit pad inside a SwiftUI screen
struct PadView: UIViewRepresentable {
    let pad: Pad
    // A VoiceOver label, if the screen wants a different one
    var label: String? = nil

    // SwiftUI calls this once. Wrap the pad in a plain view and make it stretch to fill it
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        host.addSubview(pad)
        pad.frame = host.bounds
        pad.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return host
    }

    // SwiftUI calls this when things change. Put the pad back if it moved, and update the label
    func updateUIView(_ uiView: UIView, context: Context) {
        if pad.superview !== uiView {
            uiView.addSubview(pad)
            pad.frame = uiView.bounds
        }
        if let label { pad.accessibilityLabel = label }
    }
}

// The rounded box the pad sits in
struct PadBox<Content: View>: View {
    // Wide boxes are 3 by 2, the rest are square
    var wide = false
    // The biggest a square box is allowed to get, if a screen sets one
    var cap: CGFloat? = nil
    // Whatever goes inside the box, usually a PadView
    @ViewBuilder var content: () -> Content
    // The app's colors and text sizes
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        // Rounder corners on bigger screens
        let radius: CGFloat = typo.width >= 700 ? 28 : 24
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        Group {
            if wide {
                content().aspectRatio(3 / 2, contentMode: .fit)
            } else {
                // Square boxes leave 320 points of height for the rest of the screen, and never go below 280
                content().aspectRatio(1, contentMode: .fit).frame(maxWidth: cap ?? max(typo.height - 320, 280))
            }
        }
        // Fill it, round the corners, add a thin border, and center it
        .background(shape.fill(p.surface.color))
        .clipShape(shape)
        .overlay(shape.strokeBorder(p.line.color, lineWidth: p.hair))
        .fullWidth(.center)
    }
}
