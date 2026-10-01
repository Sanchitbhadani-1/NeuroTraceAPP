import QuartzCore
import SwiftUI
import UIKit

@MainActor
private final class FrameClock: NSObject {
    var link: CADisplayLink?
    var callbacks: [Int: @MainActor (Double) -> Void] = [:]
    var nextId = 0

    func request(_ callback: @escaping @MainActor (Double) -> Void) -> Int {
        nextId += 1
        callbacks[nextId] = callback
        if link == nil {
            let made = CADisplayLink(target: self, selector: #selector(tick(_:)))
            made.add(to: .main, forMode: .common)
            link = made
        }
        link?.isPaused = false
        return nextId
    }

    @objc func tick(_ sender: CADisplayLink) {
        let due = callbacks.sorted { a, b in a.key < b.key }
        callbacks = [:]
        if due.isEmpty {
            sender.isPaused = true
            return
        }
        let now = Frames.now()
        for (_, callback) in due { callback(now) }
        if callbacks.isEmpty { sender.isPaused = true }
    }
}

// Callbacks once per screen refresh, using CADisplayLink, iOS's frame clock. Times are in
// milliseconds because the training exercises and their saved results use milliseconds
@MainActor
enum Frames {
    private static let clock = FrameClock()

    // Milliseconds since the device started. Only the difference between two readings means anything
    nonisolated static func now() -> Double { CACurrentMediaTime() * 1000 }

    // Run callback on the next screen refresh, given the time. Returns an id that cancel takes
    @discardableResult
    static func next(_ callback: @escaping @MainActor (Double) -> Void) -> Int { clock.request(callback) }

    // Stop a callback that hasn't run yet
    static func cancel(_ id: Int) { clock.callbacks[id] = nil }
}

extension Task where Success == Void, Failure == Never {
    // Run action on the main thread after a delay. Cancel the returned task to stop it running
    @discardableResult
    static func after(milliseconds ms: Double, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in
            do { try await Task<Never, Never>.sleep(for: .milliseconds(max(0, ms)), clock: .suspending) } catch { return }
            if Task<Never, Never>.isCancelled { return }
            action()
        }
    }
}

struct CubicBezier {
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double

    static let ease = CubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let easeInOut = CubicBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    static let brand = CubicBezier(x1: 0.22, y1: 1, x2: 0.36, y2: 1)

    private func sample(_ a: Double, _ b: Double, _ t: Double) -> Double {
        3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t
    }

    func callAsFunction(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            let v = sample(x1, x2, t)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return sample(y1, y2, t)
    }

    static func keyframes(_ u: Double, _ frames: [(Double, Double)], _ curve: CubicBezier) -> Double {
        var u = u.truncatingRemainder(dividingBy: 1)
        if u < 0 { u += 1 }
        for i in 1..<frames.count where u <= frames[i].0 {
            let (a, va) = frames[i - 1], (b, vb) = frames[i]
            let f = b > a ? curve((u - a) / (b - a)) : 1
            return va + (vb - va) * f
        }
        return frames[frames.count - 1].1
    }
}

@MainActor
enum Motion {
    static var app: AppModel!

    static func reduced() -> Bool { app?.motion == "reduce" }

    static func applyMotion(_ pref: String) {
        app.motion = pref == "reduce" || (pref != "full" && UIAccessibility.isReduceMotionEnabled) ? "reduce" : "full"
    }

    static func swap(_ kind: ScreenTransition = .fade, x: CGFloat? = nil, y: CGFloat? = nil, _ update: @escaping @MainActor () -> Void) {
        if reduced() || UIApplication.shared.applicationState != .active { return update() }
        if kind == .theme { return themeReveal(x: x, y: y, update) }
        app.transition = kind
        Frames.next { _ in
            withAnimation(Theme.ease(360)) { update() }
        }
    }

    private static func themeReveal(x: CGFloat?, y: CGFloat?, _ update: @MainActor () -> Void) {
        guard let window = keyWindow(), let snapshot = window.snapshotView(afterScreenUpdates: false) else { return update() }
        window.addSubview(snapshot)
        update()
        let bounds = snapshot.bounds
        let center = CGPoint(x: x ?? bounds.midX, y: y ?? bounds.midY)
        let far = 1.5 * max(bounds.width, bounds.height)
        let hole = { (r: CGFloat) -> CGPath in
            let p = UIBezierPath(rect: bounds)
            p.append(UIBezierPath(arcCenter: center, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: true))
            return p.cgPath
        }
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.path = hole(far)
        snapshot.layer.mask = mask
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { snapshot.removeFromSuperview() } }
        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = hole(0.01)
        grow.toValue = hole(far)
        grow.duration = 0.64
        grow.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
        mask.add(grow, forKey: "reveal")
        CATransaction.commit()
    }

    static func countUp(_ to: Int, from: Int = 50, ms: Double = 620, _ set: @escaping @MainActor (Int) -> Void) {
        if reduced() { return set(to) }
        let start = Frames.now()
        func tick(_ now: Double) {
            let t = min(1, (now - start) / ms)
            set(Int(jsRound(Double(from) + Double(to - from) * (1 - pow(1 - t, 3)))))
            if t < 1 { Frames.next(tick) }
        }
        Frames.next(tick)
    }

    private static var toastTimer: Task<Void, Never>?
    // ok is false for a message that isn't a success, so it shows without the checkmark
    static func toast(_ text: String, ok: Bool = true) {
        app.toastText = text
        app.toastOK = ok
        app.toastID += 1
        withAnimation(reduced() ? nil : Theme.ease(420)) { app.toastShown = true }
        UIAccessibility.post(notification: .announcement, argument: text)
        toastTimer?.cancel()
        toastTimer = Task.after(milliseconds: 1800) {
            withAnimation(reduced() ? nil : Theme.ease(420)) { app.toastShown = false }
        }
    }

    static let shell: [CGPoint] = (0...160).map { i in
        let p = Double(i) / 160, th = p * 1.6 * 2 * Double.pi, r = 62 + 88 * p
        return CGPoint(x: 170 + r * cos(th), y: 170 + r * sin(th))
    }

    static func measuring(_ min: Double = 2000) -> @MainActor () async -> (@MainActor () -> Void)? {
        if reduced() { return { nil } }
        let steps = Copy.measureSteps.count
        app.measuringOn = 0
        app.measuringHidden = false
        Frames.next { _ in withAnimation(Theme.ease(460)) { app.measuringShown = true } }
        let timers = (0..<steps).map { i in
            Task.after(milliseconds: 250 + Double(i) * ((min - 500) / Double(steps))) { withAnimation(.easeOut(duration: 0.32)) { app.measuringOn = max(app.measuringOn, i + 1) } }
        }
        let shown = Frames.now()
        return {
            try? await Task.sleep(nanoseconds: UInt64(max(0, min - (Frames.now() - shown)) * 1_000_000))
            timers.forEach { timer in timer.cancel() }
            app.measuringOn = steps
            return {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) { app.measuringShown = false }
                Task.after(milliseconds: 320) { app.measuringHidden = true }
            }
        }
    }

    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

struct Mascot: View {
    var mood = "idle"
    @Environment(\.palette) private var p
    @State private var spinAt: Double? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: Motion.reduced() && spinAt == nil)) { timeline in
            Canvas { ctx, size in
                draw(ctx, size, seconds: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if Motion.reduced() { return }
            spinAt = Frames.now()
            Task.after(milliseconds: 820) { spinAt = nil }
        }
        .accessibilityHidden(true)
    }

    private func draw(_ base: GraphicsContext, _ size: CGSize, seconds: Double) {
        let still = Motion.reduced()
        var ctx = base
        ctx.scaleBy(x: size.width / 340, y: size.height / 340)

        var bodyCtx = ctx
        if let spinAt, !still {
            let u = min(1, (Frames.now() - spinAt) / 820)
            let rot = CubicBezier.keyframes(min(u, 0.9999), [(0, 0), (0.4, 200), (1, 360)], .brand)
            let scale = CubicBezier.keyframes(min(u, 0.9999), [(0, 1), (0.4, 0.86), (1, 1)], .brand)
            bodyCtx.translateBy(x: 170, y: 170)
            bodyCtx.rotate(by: .degrees(rot))
            bodyCtx.scaleBy(x: scale, y: scale)
            bodyCtx.translateBy(x: -170, y: -170)
        } else if mood == "idle" && !still {
            let bob = CubicBezier.keyframes(seconds / 3.4, [(0, 0), (0.5, -10), (1, 0)], .easeInOut)
            bodyCtx.translateBy(x: 0, y: bob)
        } else if mood == "thinking" && !still {
            let sway = CubicBezier.keyframes(seconds / 2.6, [(0, -8), (0.5, 8), (1, -8)], .easeInOut)
            bodyCtx.translateBy(x: 170, y: 170)
            bodyCtx.rotate(by: .degrees(sway))
            bodyCtx.translateBy(x: -170, y: -170)
        }

        var shell = Path()
        shell.addLines(Motion.shell)
        if mood == "thinking" {
            var length: CGFloat = 0
            for i in 1..<Motion.shell.count {
                length += hypot(Motion.shell[i].x - Motion.shell[i - 1].x, Motion.shell[i].y - Motion.shell[i - 1].y)
            }
            let offset = CGFloat(still ? 0 : (seconds / 1.8).truncatingRemainder(dividingBy: 1))
            bodyCtx.stroke(shell, with: .color(p.accent.color), style: StrokeStyle(lineWidth: 26, lineCap: .round, dash: [0.6 * length, 0.4 * length], dashPhase: (1 - offset) * length))
        } else {
            bodyCtx.stroke(shell, with: .color(p.accent.color), style: StrokeStyle(lineWidth: 26, lineCap: .round))
        }
        bodyCtx.fill(Path(ellipseIn: CGRect(x: 170 - 54, y: 170 - 54, width: 108, height: 108)), with: .color(p.accent.color))

        var look = bodyCtx
        if mood == "thinking" && !still {
            look.translateBy(x: CubicBezier.keyframes(seconds / 2.8, [(0, -10), (0.5, 10), (1, -10)], .easeInOut), y: 0)
        }
        let blink = still ? 1 : CubicBezier.keyframes(seconds / 5.2, [(0, 1), (0.9, 1), (0.93, 0.1), (1, 1)], .ease)
        look.translateBy(x: 0, y: 166)
        look.scaleBy(x: 1, y: blink)
        look.translateBy(x: 0, y: -166)
        var eyes = Path()
        eyes.addEllipse(in: CGRect(x: 150 - 9.5, y: 166 - 14, width: 19, height: 28))
        eyes.addEllipse(in: CGRect(x: 190 - 9.5, y: 166 - 14, width: 19, height: 28))
        look.fill(eyes, with: .color(.white))
    }
}
