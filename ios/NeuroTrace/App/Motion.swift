// MOTION.SWIFT HOLDS THE APP'S TIMERS AND ANIMATIONS
// IT RUNS CODE ON EACH SCREEN REFRESH, SWAPS SCREENS, SHOWS TOASTS AND DRAWS THE SPIRAL MASCOT

import QuartzCore
import SwiftUI
import UIKit


// THE FRAME CLOCK

// Runs waiting callbacks once on each screen refresh
@MainActor
private final class FrameClock: NSObject {

    // The screen refresh timer, the waiting callbacks by id, and the last id given out
    var link: CADisplayLink?
    var callbacks: [Int: @MainActor (Double) -> Void] = [:]
    var nextId = 0

    // Add a callback to run on the next screen refresh and give back its id
    func request(_ callback: @escaping @MainActor (Double) -> Void) -> Int {

        // Save the callback under a new id
        nextId += 1
        callbacks[nextId] = callback

        // Make the screen refresh timer the first time
        if link == nil {
            let made = CADisplayLink(target: self, selector: #selector(tick(_:)))
            made.add(to: .main, forMode: .common)
            link = made
        }

        // Start the timer running and give back the id
        link?.isPaused = false
        return nextId
    }

    // Run on each screen refresh
    @objc func tick(_ sender: CADisplayLink) {

        // Take all waiting callbacks in the order they were added, and clear the list
        let due = callbacks.sorted { a, b in a.key < b.key }
        callbacks = [:]

        // Pause the timer if nothing was waiting
        if due.isEmpty {
            sender.isPaused = true
            return
        }

        // Run each callback with the current time
        let now = Frames.now()
        for (_, callback) in due { callback(now) }

        // Pause the timer if no new callbacks were added
        if callbacks.isEmpty { sender.isPaused = true }
    }
}


// Runs callbacks once per screen refresh, with times in milliseconds
@MainActor
enum Frames {

    // The one frame clock the app uses
    private static let clock = FrameClock()

    // Milliseconds since the device started
    nonisolated static func now() -> Double { CACurrentMediaTime() * 1000 }

    // Run callback on the next screen refresh with the time, and give back an id for cancel
    @discardableResult
    static func next(_ callback: @escaping @MainActor (Double) -> Void) -> Int { clock.request(callback) }

    // Remove a callback that hasn't run yet
    static func cancel(_ id: Int) { clock.callbacks[id] = nil }
}


extension Task where Success == Void, Failure == Never {

    // Run action on the main thread after ms milliseconds, and give back the task
    @discardableResult
    static func after(milliseconds ms: Double, _ action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        Task { @MainActor in

            // Wait, and stop if the task is cancelled while waiting
            do { try await Task<Never, Never>.sleep(for: .milliseconds(max(0, ms)), clock: .suspending) } catch { return }
            if Task<Never, Never>.isCancelled { return }

            // Run the action
            action()
        }
    }
}


// THE EASING CURVES

// An easing curve made from two control points, like the ones in CSS
struct CubicBezier {

    // The x and y of the two control points
    var x1: Double
    var y1: Double
    var x2: Double
    var y2: Double

    // The standard ease curve, the ease in and out curve, and the app's own curve
    static let ease = CubicBezier(x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
    static let easeInOut = CubicBezier(x1: 0.42, y1: 0, x2: 0.58, y2: 1)
    static let brand = CubicBezier(x1: 0.22, y1: 1, x2: 0.36, y2: 1)

    // One coordinate of the curve at point t along it, given the two control values
    private func sample(_ a: Double, _ b: Double, _ t: Double) -> Double {
        3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t
    }

    // Give back the curve's y value for an x value from 0 to 1
    func callAsFunction(_ x: Double) -> Double {

        // Keep the answer at 0 or 1 outside the range
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }

        // Halve the search range up to 40 times to find the point t where the curve's x matches
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            let v = sample(x1, x2, t)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }

        // Give back the curve's y at that point
        return sample(y1, y2, t)
    }

    // Give back a value at time u from a list of (time, value) frames, easing between them with curve
    static func keyframes(_ u: Double, _ frames: [(Double, Double)], _ curve: CubicBezier) -> Double {

        // Wrap u to between 0 and 1
        var u = u.truncatingRemainder(dividingBy: 1)
        if u < 0 { u += 1 }

        // Find the two frames u falls between and ease from one value to the next
        for i in 1..<frames.count where u <= frames[i].0 {
            let (a, va) = frames[i - 1], (b, vb) = frames[i]
            let f = b > a ? curve((u - a) / (b - a)) : 1
            return va + (vb - va) * f
        }

        // After the last frame, give back the last value
        return frames[frames.count - 1].1
    }
}


// THE APP'S ANIMATIONS

// The app wide animations, each one skipped or shortened when Reduced Motion is on
@MainActor
enum Motion {

    // The main app model
    static var app: AppModel!

    // True when the app's motion setting is "reduce"
    static func reduced() -> Bool { app?.motion == "reduce" }

    // Set the motion setting to "reduce" if the person picked it, or picked neither and iOS has Reduce Motion on, and "full" otherwise
    static func applyMotion(_ pref: String) {
        app.motion = pref == "reduce" || (pref != "full" && UIAccessibility.isReduceMotionEnabled) ? "reduce" : "full"
    }

    // Change the screen with an animation of the given kind
    static func swap(_ kind: ScreenTransition = .fade, x: CGFloat? = nil, y: CGFloat? = nil, _ update: @escaping @MainActor () -> Void) {

        // Change it right away with Reduced Motion on or when the app isn't in front
        if reduced() || UIApplication.shared.applicationState != .active { return update() }

        // Use the growing circle for a theme change
        if kind == .theme { return themeReveal(x: x, y: y, update) }

        // Otherwise set the transition and animate the change on the next screen refresh
        app.transition = kind
        Frames.next { _ in
            withAnimation(Theme.ease(360)) { update() }
        }
    }

    // Show the new theme through a circle that grows out from the point x, y
    private static func themeReveal(x: CGFloat?, y: CGFloat?, _ update: @MainActor () -> Void) {

        // Put a picture of the old screen on top, then change the theme underneath it
        guard let window = keyWindow(), let snapshot = window.snapshotView(afterScreenUpdates: false) else { return update() }
        window.addSubview(snapshot)
        update()

        // The center of the circle, or the middle of the screen, and a radius bigger than the screen
        let bounds = snapshot.bounds
        let center = CGPoint(x: x ?? bounds.midX, y: y ?? bounds.midY)
        let far = 1.5 * max(bounds.width, bounds.height)

        // A shape that covers the screen with a round hole of radius r
        let hole = { (r: CGFloat) -> CGPath in
            let p = UIBezierPath(rect: bounds)
            p.append(UIBezierPath(arcCenter: center, radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: true))
            return p.cgPath
        }

        // Cut the hole out of the old screen picture
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.path = hole(far)
        snapshot.layer.mask = mask

        // Grow the hole from almost nothing to past the edges over 0.64 seconds, then remove the picture
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

    // Count a number up from `from` to `to` over ms milliseconds, passing each step to set
    static func countUp(_ to: Int, from: Int = 50, ms: Double = 620, _ set: @escaping @MainActor (Int) -> Void) {

        // With Reduced Motion on, jump straight to the end number
        if reduced() { return set(to) }
        let start = Frames.now()

        // On each screen refresh, set the number along a curve that slows at the end, until the time is up
        func tick(_ now: Double) {
            let t = min(1, (now - start) / ms)
            set(Int(jsRound(Double(from) + Double(to - from) * (1 - pow(1 - t, 3)))))
            if t < 1 { Frames.next(tick) }
        }
        Frames.next(tick)
    }

    // The timer that hides the toast
    private static var toastTimer: Task<Void, Never>?

    // Show a short message at the bottom of the screen, with a checkmark when ok is true
    static func toast(_ text: String, ok: Bool = true) {

        // Set the message and slide it in
        app.toastText = text
        app.toastOK = ok
        app.toastID += 1
        withAnimation(reduced() ? nil : Theme.ease(420)) { app.toastShown = true }

        // Have VoiceOver read the message out
        UIAccessibility.post(notification: .announcement, argument: text)

        // Hide the message after 1.8 seconds, restarting the timer if one was running
        toastTimer?.cancel()
        toastTimer = Task.after(milliseconds: 1800) {
            withAnimation(reduced() ? nil : Theme.ease(420)) { app.toastShown = false }
        }
    }

    // The 161 points of the mascot's spiral shell, in a 340 by 340 box
    static let shell: [CGPoint] = (0...160).map { i in
        let p = Double(i) / 160, th = p * 1.6 * 2 * Double.pi, r = 62 + 88 * p
        return CGPoint(x: 170 + r * cos(th), y: 170 + r * sin(th))
    }

    // Show the measuring screen with its steps ticking on, and give back a function that waits at least min milliseconds and then gives back a function that hides it
    static func measuring(_ min: Double = 2000) -> @MainActor () async -> (@MainActor () -> Void)? {

        // With Reduced Motion on, skip the measuring screen
        if reduced() { return { nil } }

        // Reset the steps and fade the measuring screen in
        let steps = Copy.measureSteps.count
        app.measuringOn = 0
        app.measuringHidden = false
        Frames.next { _ in withAnimation(Theme.ease(460)) { app.measuringShown = true } }

        // Tick each step on at an even spacing across the wait
        let timers = (0..<steps).map { i in
            Task.after(milliseconds: 250 + Double(i) * ((min - 500) / Double(steps))) { withAnimation(.easeOut(duration: 0.32)) { app.measuringOn = max(app.measuringOn, i + 1) } }
        }
        let shown = Frames.now()
        return {

            // Wait out the rest of the min time, then stop the timers and tick on every step
            try? await Task.sleep(nanoseconds: UInt64(max(0, min - (Frames.now() - shown)) * 1_000_000))
            timers.forEach { timer in timer.cancel() }
            app.measuringOn = steps

            // Give back a function that fades the measuring screen out and then removes it
            return {
                withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 0.3)) { app.measuringShown = false }
                Task.after(milliseconds: 320) { app.measuringHidden = true }
            }
        }
    }

    // The app window that is in front right now
    static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}


// THE MASCOT

// The spiral shell mascot with eyes, which bobs, sways, blinks and spins when tapped
struct Mascot: View {

    // What the mascot is doing, "idle" or "thinking"
    var mood = "idle"

    // The colors, and when the spin started, or nil when it isn't spinning
    @Environment(\.palette) private var p
    @State private var spinAt: Double? = nil

    var body: some View {

        // Redraw the mascot on every screen refresh, paused with Reduced Motion on and no spin
        TimelineView(.animation(minimumInterval: nil, paused: Motion.reduced() && spinAt == nil)) { timeline in
            Canvas { ctx, size in
                draw(ctx, size, seconds: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .contentShape(Rectangle())
        // Spin for 820 milliseconds when tapped, unless Reduced Motion is on
        .onTapGesture {
            if Motion.reduced() { return }
            spinAt = Frames.now()
            Task.after(milliseconds: 820) { spinAt = nil }
        }
        // Screen readers skip the mascot
        .accessibilityHidden(true)
    }

    // Draw the mascot at a moment in time
    private func draw(_ base: GraphicsContext, _ size: CGSize, seconds: Double) {

        // Scale the 340 by 340 drawing to fit the space
        let still = Motion.reduced()
        var ctx = base
        ctx.scaleBy(x: size.width / 340, y: size.height / 340)

        // Move the body for a spin, an idle bob or a thinking sway
        var bodyCtx = ctx
        if let spinAt, !still {

            // Spin all the way around the center, shrinking a little partway through
            let u = min(1, (Frames.now() - spinAt) / 820)
            let rot = CubicBezier.keyframes(min(u, 0.9999), [(0, 0), (0.4, 200), (1, 360)], .brand)
            let scale = CubicBezier.keyframes(min(u, 0.9999), [(0, 1), (0.4, 0.86), (1, 1)], .brand)
            bodyCtx.translateBy(x: 170, y: 170)
            bodyCtx.rotate(by: .degrees(rot))
            bodyCtx.scaleBy(x: scale, y: scale)
            bodyCtx.translateBy(x: -170, y: -170)
        } else if mood == "idle" && !still {

            // Bob up 10 points and back every 3.4 seconds
            let bob = CubicBezier.keyframes(seconds / 3.4, [(0, 0), (0.5, -10), (1, 0)], .easeInOut)
            bodyCtx.translateBy(x: 0, y: bob)
        } else if mood == "thinking" && !still {

            // Tilt 8 degrees each way around the center every 2.6 seconds
            let sway = CubicBezier.keyframes(seconds / 2.6, [(0, -8), (0.5, 8), (1, -8)], .easeInOut)
            bodyCtx.translateBy(x: 170, y: 170)
            bodyCtx.rotate(by: .degrees(sway))
            bodyCtx.translateBy(x: -170, y: -170)
        }

        // The spiral shell line
        var shell = Path()
        shell.addLines(Motion.shell)
        if mood == "thinking" {

            // While thinking, add up the shell's length and draw it as a dash that runs along it every 1.8 seconds
            var length: CGFloat = 0
            for i in 1..<Motion.shell.count {
                length += hypot(Motion.shell[i].x - Motion.shell[i - 1].x, Motion.shell[i].y - Motion.shell[i - 1].y)
            }
            let offset = CGFloat(still ? 0 : (seconds / 1.8).truncatingRemainder(dividingBy: 1))
            bodyCtx.stroke(shell, with: .color(p.accent.color), style: StrokeStyle(lineWidth: 26, lineCap: .round, dash: [0.6 * length, 0.4 * length], dashPhase: (1 - offset) * length))
        } else {

            // Otherwise draw the whole shell as one solid line
            bodyCtx.stroke(shell, with: .color(p.accent.color), style: StrokeStyle(lineWidth: 26, lineCap: .round))
        }

        // The round head in the middle
        bodyCtx.fill(Path(ellipseIn: CGRect(x: 170 - 54, y: 170 - 54, width: 108, height: 108)), with: .color(p.accent.color))

        // While thinking, move the eyes 10 points left and right every 2.8 seconds
        var look = bodyCtx
        if mood == "thinking" && !still {
            look.translateBy(x: CubicBezier.keyframes(seconds / 2.8, [(0, -10), (0.5, 10), (1, -10)], .easeInOut), y: 0)
        }

        // Squash the eyes flat for a quick blink every 5.2 seconds
        let blink = still ? 1 : CubicBezier.keyframes(seconds / 5.2, [(0, 1), (0.9, 1), (0.93, 0.1), (1, 1)], .ease)
        look.translateBy(x: 0, y: 166)
        look.scaleBy(x: 1, y: blink)
        look.translateBy(x: 0, y: -166)

        // The two white oval eyes
        var eyes = Path()
        eyes.addEllipse(in: CGRect(x: 150 - 9.5, y: 166 - 14, width: 19, height: 28))
        eyes.addEllipse(in: CGRect(x: 190 - 9.5, y: 166 - 14, width: 19, height: 28))
        look.fill(eyes, with: .color(.white))
    }
}
