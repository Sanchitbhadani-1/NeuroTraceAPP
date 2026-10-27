// EXERCISESCREEN.SWIFT RUNS ONE REHAB EXERCISE AND SHOWS HOW IT WENT
// IT DRAWS THE GUIDES, RUNS THE DEMO, METRONOME AND TARGETS, SCORES EACH TRY AND MOVES THE LEVEL UP OR DOWN

import AVFoundation
import SwiftUI
import UIKit

// The demo lasts 4 seconds and the imagine countdown counts down from 4
private let demoSecs = 4.0, imagineSecs = 4

// The pause between targets, in milliseconds
private let gapMs = 400.0

// How many points outside a target a tap can land and still catch it
private let tapSlack = 6.0


// THE PIECES OF A TRY

// What the result card shows after a try
struct ExResult {
    var verdict: String
    var notes: [String]
    var rows: [(String, String)]
    var levelNote: String?
}


// One target circle, with where it is, how big it is, and when it showed up in milliseconds
private struct Target {
    var x: Double
    var y: Double
    var size: Double
    var at: Double
}


// One round of targets
private struct Round {

    // Whether each target was caught, and the taps that missed every target
    var results: [Train.TargetResult] = []
    var extra = 0

    // The target on screen now, or nil if there is none
    var target: Target? = nil

    // Whether an Apple Pencil was used, and the kind of input of the first tap
    var pencilSeen = false
    var inputType: String? = nil
}


// What each exercise uses to draw, run and score a try
private struct ExUI {

    // The pad shape, "wide", "square" or "tap"
    var pad: String

    // What to draw under the ink and over the ink
    var guide: PadDraw? = nil
    var overlay: PadDraw? = nil

    // What to run when a try begins, when Start over is tapped, and when Start is tapped
    var begin: @MainActor () -> Void
    var clear: (@MainActor () -> Void)? = nil
    var start: (@MainActor () -> Void)? = nil

    // Scores the drawing and gives back the outcome and the pad's measurements
    var score: (@MainActor ([Sample], [Int], Double, Double, [[String: Double]]) -> (out: Train.Outcome, geometry: [String: Double]))? = nil

    // The message for a drawing too short to score
    var tooShort: String? = nil

    // Turns the outcome into the rows on the result card
    var rows: @MainActor (Train.Outcome) -> [(String, String)]
}


// THE METRONOME

// Plays the clicks for the rhythm exercise
@MainActor
private final class Metronome {

    // The audio engine, the player, and the sound format of 44100 samples a second on one channel
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let rate = 44100.0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    // Connect the player to the engine's output
    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    // The start time for clicks, always 0
    var currentTime: Double { 0 }

    // Set up the sound session in the background
    static func prepare() {
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    // Build a sound with a click at each time given, in seconds, and play it
    func play(_ clicks: [(at: Double, accent: Bool)]) throws {

        // Start the engine if it isn't running
        if !engine.isRunning { try engine.start() }

        // Make a silent sound that lasts until 0.1 seconds after the last click
        let end = (clicks.map { c in c.at }.max() ?? 0) + 0.1
        let frames = AVAudioFrameCount(end * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        let total = Int(frames)
        for i in 0..<total { data[i] = 0 }

        // Add each click
        for click in clicks {

            // A higher tone for an accented click
            let f = click.accent ? 1320.0 : 880.0
            let first = Int(click.at * rate)

            // Each click lasts 0.08 seconds
            for n in 0..<Int(0.08 * rate) where first + n < total {
                let t = Double(n) / rate

                // The volume rises fast for 0.004 seconds, then fades out by 0.07 seconds
                let g = t < 0.004 ? 0.0001 * pow(0.5 / 0.0001, t / 0.004) : t < 0.07 ? 0.5 * pow(0.0001 / 0.5, (t - 0.004) / 0.066) : 0.0001
                data[first + n] += Float(g * sin(2 * Double.pi * f * t))
            }
        }

        // Stop anything playing and play the new sound
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    // Stop the sound
    func stop() { player.stop() }
}


// THE TAPPING AREA

// The area where the target circles show up and taps are caught
final class TapCanvas: UIView {

    // What to run on each tap, when the area changes size, and to draw the area
    var onTap: ((UITouch) -> Void)?
    var onResize: (() -> Void)?
    var paint: ((CGContext) -> Void)?

    // Make a see through area that redraws on resize, takes many touches at once, and has a screen reader label
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isMultipleTouchEnabled = true
        isAccessibilityElement = true
        accessibilityTraits = [.image, .allowsDirectInteraction]
        accessibilityLabel = "Tapping area. Circles appear here one at a time."
    }

    // Making the area from a storyboard is not supported
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Block drag gestures on the area
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        !(gestureRecognizer is UIPanGestureRecognizer)
    }

    // Draw the area with paint
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        paint?(ctx)
    }

    // Run onResize when the area is laid out
    override func layoutSubviews() {
        super.layoutSubviews()
        onResize?()
    }

    // Run onTap for each new touch
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { onTap?(touch) }
    }
}


// Puts the tapping area inside a SwiftUI view
private struct TapView: UIViewRepresentable {

    // The tapping area
    let canvas: TapCanvas

    // Make a clear view with the tapping area filling it
    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        host.addSubview(canvas)
        canvas.frame = host.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return host
    }

    // Put the tapping area back in this view if it was moved to another one
    func updateUIView(_ uiView: UIView, context: Context) {
        if canvas.superview !== uiView {
            uiView.addSubview(canvas)
            canvas.frame = uiView.bounds
        }
    }
}



// THE EXERCISE MODEL

// Holds what the exercise screen needs, and runs and scores each try
@MainActor
@Observable
final class ExerciseModel {

    // The main app model
    unowned let app: AppModel

    // The exercise ID and the text on the screen
    var id = ""
    var title = ""
    var instruction = ""
    var padLabel = ""
    var levelText = ""
    var phaseText = ""

    // The hits and misses so far, and whether this is the top level
    var hits = 0
    var misses = 0
    var top = false

    // Which buttons show, the pad shape, and whether Done is turned off
    var actions: String? = "draw"
    var padKind = "wide"
    var doneDisabled = true

    // The status line and what shakes it
    var status: String? = nil
    let shaker = Shaker()

    // The result of the last try, and a count that goes up to scroll to the result
    var result: ExResult? = nil
    var scrollToResult = 0

    // The level state, the target for each level, the part of the try, and the loop marks
    @ObservationIgnored private var state = Train.newLevelState()
    @ObservationIgnored private var levels: [Double] = []
    @ObservationIgnored private var phase: String? = nil
    @ObservationIgnored private var marks: [Train.LoopMark]? = nil

    // How far the demo has gone, where the rhythm dot is in beats, and when the rhythm dot started
    @ObservationIgnored private var demoAt: Double? = nil
    @ObservationIgnored private var dotBeat: Double? = nil
    @ObservationIgnored private var dotStart: Double? = nil

    // True while the pad is locked
    @ObservationIgnored private var inert = false

    // The timers, the animation frame, the clicks and the metronome
    @ObservationIgnored private var exTimers: [Task<Void, Never>] = []
    @ObservationIgnored private var exFrame = 0
    @ObservationIgnored private var exClicks: [(at: Double, accent: Bool)] = []
    @ObservationIgnored private var audio: Metronome? = nil

    // The round of targets, the tapping area's size, and when it was last painted
    @ObservationIgnored private var round: Round? = nil
    @ObservationIgnored private var tapW = 0.0
    @ObservationIgnored private var tapH = 0.0
    @ObservationIgnored private var paintAt = 0.0

    // The spiral and wave paths, kept for the pad size they were made for
    @ObservationIgnored private var spiralCache: (path: Train.Path, w: Double, h: Double)? = nil
    @ObservationIgnored private var waveCache: (path: Train.Path, w: Double, h: Double)? = nil

    // The drawing pad, which draws this exercise's guide and overlay
    @ObservationIgnored lazy var exPad: Pad = createPad(
        onInk: { [weak self] cleared in self?.onInk(cleared) },
        guide: { [weak self] ctx, w, h in
            guard let self, !self.id.isEmpty else { return }
            self.exUI().guide?(ctx, w, h)
        },
        overlay: { [weak self] ctx, w, h in
            guard let self, !self.id.isEmpty else { return }
            self.exUI().overlay?(ctx, w, h)
        }
    )

    // The tapping area, which draws the target, resizes, and handles taps
    @ObservationIgnored lazy var tapCanvas: TapCanvas = {
        let canvas = TapCanvas(frame: .zero)
        canvas.paint = { [weak self] ctx in MainActor.assumeIsolated { self?.drawTarget(ctx) } }

        // On resize, store the new size and repaint, only for the tapping exercise
        canvas.onResize = { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.padKind == "tap" else { return }
                self.sizeTapCanvas()
                self.paintTarget()
            }
        }
        canvas.onTap = { [weak self] touch in MainActor.assumeIsolated { self?.tapped(touch) } }
        return canvas
    }()

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // The target for the current level
    private func exTarget() -> Double { levels[state.level] }

    // Stop the timers, the animation and the sound, and clear the clicks
    func exStop() {
        exTimers.forEach { t in t.cancel() }
        exTimers = []
        Frames.cancel(exFrame)
        audio?.stop()
        exClicks = []
    }

    // Run a function after a number of milliseconds
    private func exAfter(_ ms: Double, _ fn: @escaping @MainActor () -> Void) { exTimers.append(Task.after(milliseconds: ms, fn)) }

    // Set the phase text, or clear it with nil
    private func exPhase(_ text: String?) { phaseText = text ?? "" }

    // Set which buttons show
    private func exActions(_ which: String?) { actions = which }

    // Lock or unlock the pad
    private func setInert(_ on: Bool) {
        inert = on
        exPad.isUserInteractionEnabled = !on
    }

    // Turn Done on when the pad is unlocked and has ink, and say so if the drawing was cleared
    private func onInk(_ cleared: String?) {
        doneDisabled = inert || !exPad.hasInk()
        showStatus(cleared != nil ? Copy.resizeCleared : nil)
    }

    // Show a sentence in the status line, shake it and read it out, or clear it with nil
    private func showStatus(_ sentence: String?) {
        status = sentence
        guard let sentence else { return }
        shaker.shake()
        UIAccessibility.post(notification: .announcement, argument: sentence)
    }


    // DRAWING HELPERS

    // Draw a line through the points of a path, up to a point number or to the end
    private func strokePath(_ ctx: CGContext, _ path: Train.Path, _ upTo: Int? = nil) {
        ctx.beginPath()
        for i in 0..<(upTo ?? path.x.count) {
            if i == 0 { ctx.move(to: CGPoint(x: path.x[i], y: path.y[i])) } else { ctx.addLine(to: CGPoint(x: path.x[i], y: path.y[i])) }
        }
        ctx.strokePath()
    }

    // Draw a filled dot in the accent color
    private func dot(_ ctx: CGContext, _ x: Double, _ y: Double, _ r: Double) {
        ctx.setFillColor(Palette.current.accent.ui.cgColor)
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.fillPath()
    }


    // BIG WRITING

    // Work out where the lines go, with the baseline at 80% of the height and the target line above it by share of the height
    private func writingGeometry(_ w: Double, _ h: Double, _ share: Double) -> (baselineY: Double, targetPx: Double, targetY: Double, left: Double, right: Double) {
        let baselineY = h * 0.8
        return (baselineY: baselineY, targetPx: h * share, targetY: baselineY - h * share, left: w * 0.06, right: w * 0.94)
    }

    // Draw the baseline, the dashed target line and its label
    private func bigWritingGuide(_ ctx: CGContext, _ cw: CGFloat, _ ch: CGFloat) {
        let g = writingGeometry(Double(cw), Double(ch), exTarget())
        ctx.saveGState()

        // The gray baseline
        ctx.setLineWidth(2)
        ctx.setStrokeColor(Palette.current.guide.ui.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: g.left, y: g.baselineY))
        ctx.addLine(to: CGPoint(x: g.right, y: g.baselineY))
        ctx.strokePath()

        // The dashed target line in the accent color
        ctx.setLineDash(phase: 0, lengths: [10, 8])
        ctx.setStrokeColor(Palette.current.accent.ui.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: g.left, y: g.targetY))
        ctx.addLine(to: CGPoint(x: g.right, y: g.targetY))
        ctx.strokePath()

        // The label just above the right end of the target line
        let font = Fonts.make(.body(15, 600), size: 15)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.current.ink2.ui]
        let label = Copy.targetLabel as NSString
        let size = label.size(withAttributes: attributes)
        UIGraphicsPushContext(ctx)
        label.draw(at: CGPoint(x: g.right - Double(size.width), y: g.targetY - 10 - Double(font.ascender)), withAttributes: attributes)
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

    // Draw a small circle above each loop, filled in if the loop reached the target line
    private func loopMarks(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat) {
        guard let marks, exPad.hasInk() else { return }
        ctx.saveGState()
        ctx.setLineWidth(2.5)
        for mark in marks {
            ctx.beginPath()
            ctx.addArc(center: CGPoint(x: mark.x, y: mark.y - 14), radius: 6, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
            ctx.setFillColor((mark.reached ? Palette.current.accent.ui : Palette.current.surface.ui).cgColor)
            ctx.setStrokeColor(Palette.current.accent.ui.cgColor)
            ctx.drawPath(using: .fillStroke)
        }
        ctx.restoreGState()
    }

    // Unlock the pad and show the drawing buttons
    private func beginDrawing() {
        setInert(false)
        exActions("draw")
        exPhase(nil)
    }

    // Score a big writing try against the baseline and target line
    private func scoreBigWritingTry(_ samples: [Sample], _ starts: [Int], _ w: Double, _ h: Double, _ recent: [[String: Double]]) -> (out: Train.Outcome, geometry: [String: Double]) {
        let geo = writingGeometry(w, h, exTarget())
        return (
            out: Train.scoreBigWriting(samples, starts, (baselineY: geo.baselineY, targetPx: geo.targetPx), recent),
            geometry: ["width": w, "height": h, "baselineY": geo.baselineY, "targetPx": geo.targetPx]
        )
    }


    // STEADY TRACING

    // The spiral path for this pad size, made again only when the size changes
    private func spiralFor(_ w: Double, _ h: Double) -> Train.Path {
        if spiralCache?.w != w || spiralCache?.h != h { spiralCache = (path: Train.tracingPath(w, h), w: w, h: h) }
        return spiralCache!.path
    }

    // Draw the gray spiral and the start dot
    private func tracingGuide(_ ctx: CGContext, _ cw: CGFloat, _ ch: CGFloat) {
        let path = spiralFor(Double(cw), Double(ch))

        // The spiral is fully shown, or faded to the level's target while tracing
        let visibility = phase == "trace" ? exTarget() : 1
        if visibility > 0 {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(visibility))
            ctx.setStrokeColor(Palette.current.guide.ui.cgColor)
            ctx.setLineWidth(max(2, cw / 180))
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            strokePath(ctx, path)
            ctx.restoreGState()
        }
        dot(ctx, path.x[0], path.y[0], 7.5)
    }

    // During the demo, draw the spiral as far as the demo has gone, with a dot at the tip
    private func tracingOverlay(_ ctx: CGContext, _ cw: CGFloat, _ ch: CGFloat) {
        guard phase == "watch", let demoAt else { return }
        let path = spiralFor(Double(cw), Double(ch))
        let along = demoAt * path.length

        // The part of the spiral drawn so far
        ctx.saveGState()
        ctx.setStrokeColor(Palette.current.accent.ui.cgColor)
        ctx.setLineWidth(max(3, cw / 110))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let upTo = path.s.firstIndex { s in s > along }
        strokePath(ctx, path, upTo ?? path.x.count)
        ctx.restoreGState()

        // The dot at the tip
        let (x, y) = Train.pointAlong(path, along)
        dot(ctx, x, y, 9)
    }

    // Show the demo, count down while the person imagines tracing, then let them trace
    private func beginTracing() {

        // Lock the pad for the demo
        phase = "watch"
        setInert(true)
        exActions("draw")
        doneDisabled = true

        // Hide the demo and count down once a second, then unlock the pad for tracing
        func imagine() {
            phase = "imagine"
            demoAt = nil
            exPad.redraw()
            var left = imagineSecs
            func tick() {
                if left == 0 {
                    phase = "trace"
                    exPad.redraw()
                    setInert(false)
                    return exPhase(Copy.traceNow)
                }
                exPhase(Copy.imagine(left))
                left -= 1
                exAfter(1000, tick)
            }
            tick()
        }

        // With Reduced Motion on, show the whole spiral for 2.5 seconds with no demo
        if Motion.reduced() {
            exPhase(Copy.look)
            exPad.redraw()
            return exAfter(2500, imagine)
        }

        // Draw the demo frame by frame over demoSecs, then start imagining after 600 milliseconds
        exPhase(Copy.watch)
        let t0 = Frames.now()
        func step(_ now: Double) {
            demoAt = min(1, (now - t0) / 1000 / demoSecs)
            exPad.redraw()
            if (demoAt ?? 1) < 1 { exFrame = Frames.next(step) } else { exAfter(600, imagine) }
        }
        exFrame = Frames.next(step)
    }

    // Clear the tracing, or start a new try if tracing hasn't begun
    private func clearTracing() {
        if phase != "trace" { return exNewTry() }
        exPad.reset()
        setInert(false)
        doneDisabled = true
        showStatus(nil)
    }

    // Score a tracing try against the spiral
    private func scoreTracingTry(_ samples: [Sample], _ starts: [Int], _ w: Double, _ h: Double, _ recent: [[String: Double]]) -> (out: Train.Outcome, geometry: [String: Double]) {
        let path = spiralFor(w, h)
        return (
            out: Train.scoreTracing(samples, starts, path, recent),
            geometry: ["width": w, "height": h, "radius": path.radius, "visibility": exTarget()]
        )
    }


    // RHYTHM

    // The wave path for this pad size, made again only when the size changes
    private func waveFor(_ w: Double, _ h: Double) -> Train.Path {
        if waveCache?.w != w || waveCache?.h != h { waveCache = (path: Train.rhythmPath(w, h), w: w, h: h) }
        return waveCache!.path
    }

    // Draw the gray wave
    private func rhythmGuide(_ ctx: CGContext, _ cw: CGFloat, _ ch: CGFloat) {
        ctx.saveGState()
        ctx.setStrokeColor(Palette.current.guide.ui.cgColor)
        ctx.setLineWidth(max(2, cw / 180))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        strokePath(ctx, waveFor(Double(cw), Double(ch)))
        ctx.restoreGState()
    }

    // Draw the dot on the wave at the current beat, until the try is done
    private func rhythmOverlay(_ ctx: CGContext, _ cw: CGFloat, _ ch: CGFloat) {
        guard phase != "done", let wave = waveCache?.path else { return }
        let (x, y) = Train.pointAlong(wave, (dotBeat ?? 0) * wave.beatLength)
        ctx.saveGState()
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: x, y: y), radius: 11, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.setFillColor(Palette.current.accent.ui.cgColor)
        ctx.setStrokeColor(Palette.current.surface.ui.cgColor)
        ctx.setLineWidth(3)
        ctx.drawPath(using: .fillStroke)
        ctx.restoreGState()
    }

    // Put the dot at the start, lock the pad and show the Start button
    private func beginRhythm() {
        phase = "ready"
        dotBeat = 0
        setInert(true)
        exActions("start")
        exPhase(Copy.rhythmReady)
        exPad.redraw()
    }

    // Add a click at a time in seconds
    private func click(_ at: Double, _ accent: Bool) {
        exClicks.append((at: at, accent: accent))
    }

    // Play the metronome and move the dot along the wave, one bump per beat
    private func startRhythm() {

        // The seconds per beat at the level's beats per minute, and a 0.15 second lead before the first click
        let beatSec = 60 / exTarget()
        let lead = 0.15

        // Add a click for each count in beat and each beat, with the first beat after the count in accented, and play them
        do {
            if audio == nil { audio = Metronome() }
            let t0 = (audio?.currentTime ?? 0) + lead
            for k in 0...Int(Train.countIn + Train.rhythmBeats) { click(t0 + Double(k) * beatSec, Double(k) == Train.countIn) }
            try audio?.play(exClicks)
        } catch {
            print("NeuroTrace: no metronome sound", error)
        }

        // The dot starts moving after the lead and the count in
        dotStart = Frames.now() + (lead + Train.countIn * beatSec) * 1000

        // Unlock the pad and show the drawing buttons
        phase = "count"
        setInert(false)
        exActions("draw")
        doneDisabled = !exPad.hasInk()

        // Each frame, show the count in, then move the dot until the last beat
        func step(_ now: Double) {
            let t = (now - (dotStart ?? now)) / 1000

            // Before the dot starts show the beats left, and once it starts show the follow text
            if t < 0 { exPhase(Copy.getReady(Int(min(Train.countIn, ceil(-t / beatSec))))) }
            else if phase == "count" {
                phase = "run"
                exPhase(Copy.follow)
            }

            // Move the dot to the current beat
            dotBeat = min(Train.rhythmBeats, max(0, t / beatSec))
            exPad.redraw()

            // Keep going until the last beat, then show the end text
            if t < Train.rhythmBeats * beatSec { exFrame = Frames.next(step) }
            else {
                phase = "end"
                exPhase(Copy.rhythmEnd)
            }
        }
        exFrame = Frames.next(step)
    }

    // Score a rhythm try against the wave and the beat
    private func scoreRhythmTry(_ samples: [Sample], _ starts: [Int], _ w: Double, _ h: Double, _ recent: [[String: Double]]) -> (out: Train.Outcome, geometry: [String: Double]) {
        let beatSec = 60 / exTarget()

        // The seconds from when the dot started to when the pen first touched, or 0 if either is missing
        let first = exPad.startedAt()
        let penOffset = dotStart != nil && first != nil ? (first! - dotStart!) / 1000 : 0
        return (
            out: Train.scoreRhythm(samples, starts, waveFor(w, h), (beatSec: beatSec, penOffset: penOffset), recent),
            geometry: ["width": w, "height": h, "bpm": exTarget(), "penOffset": penOffset]
        )
    }


    // TARGETS

    // Store the tapping area's size
    private func sizeTapCanvas() {
        tapW = Double(tapCanvas.bounds.width)
        tapH = Double(tapCanvas.bounds.height)
    }

    // Repaint the tapping area as of a time
    private func paintTarget(_ now: Double = Frames.now()) {
        paintAt = now
        tapCanvas.setNeedsDisplay()
    }

    // Clear the tapping area and draw the target at its size for how long it has been showing
    private func drawTarget(_ ctx: CGContext) {
        ctx.clear(CGRect(x: 0, y: 0, width: tapW, height: tapH))
        guard let t = round?.target else { return }
        let r = Train.targetRadius(t.size, (paintAt - t.at) / 1000)
        if r > 0 { dot(ctx, t.x, t.y, r) }
    }

    // Show the Start button, then size and paint the tapping area on the next frame
    private func beginTargets() {
        phase = "ready"
        round = nil
        exActions("start")
        exPhase(Copy.targetsReady)
        Frames.next { _ in
            self.sizeTapCanvas()
            self.paintTarget()
        }
    }

    // Start a new round and show the first target after 600 milliseconds
    private func startTargets() {
        phase = "run"
        exActions(nil)
        round = Round()
        sizeTapCanvas()
        exAfter(600, nextTarget)
    }

    // Show the next target, or end the round once every target has shown
    private func nextTarget() {
        guard round != nil else { return }
        if (round?.results.count ?? 0) >= Train.targets { return endRound() }

        // Put the target at a random spot, at least half its size plus 8 points from each edge
        let size = exTarget(), m = size / 2 + 8
        round?.target = Target(x: m + Double.random(in: 0..<1) * (tapW - 2 * m), y: m + Double.random(in: 0..<1) * (tapH - 2 * m), size: size, at: Frames.now())
        exPhase(Copy.circleOf((round?.results.count ?? 0) + 1, Train.targets))

        // Each frame, repaint the target, and once it has shrunk away count a miss and show the next one after the gap
        func step(_ now: Double) {
            guard let t = round?.target else { return }
            if Train.targetRadius(t.size, (now - t.at) / 1000) <= 0 {
                round?.results.append(Train.TargetResult(caught: false, ms: nil))
                round?.target = nil
                paintTarget(now)
                return exAfter(gapMs, nextTarget)
            }
            paintTarget(now)
            exFrame = Frames.next(step)
        }
        exFrame = Frames.next(step)
    }

    // Handle a tap on the tapping area
    private func tapped(_ e: UITouch) {

        // Do nothing unless a round is running
        if phase != "run" || round == nil { return }

        // Note an Apple Pencil, ignore finger taps once a Pencil was used, and keep the first kind of input
        let kind = InputKind(e)
        if kind == .pencil { round?.pencilSeen = true }
        if kind == .touch && round?.pencilSeen == true { return }
        if round?.inputType == nil { round?.inputType = kind.rawValue }

        // Find where and when the tap was, and the target's size at that time
        let t = round?.target
        let point = e.location(in: tapCanvas)
        let x = Double(point.x), y = Double(point.y)
        let stamp = e.timestamp * 1000
        let r = t.map { t in Train.targetRadius(t.size, (stamp - t.at) / 1000) } ?? 0

        // A tap inside the target plus tapSlack catches it, records the time, buzzes and shows the next target after the gap
        if let t, r > 0 && hypot(x - t.x, y - t.y) <= r + tapSlack {
            round?.results.append(Train.TargetResult(caught: true, ms: jsRound(stamp - t.at)))
            round?.target = nil
            Frames.cancel(exFrame)
            paintTarget()
            vibrate(10)
            exAfter(gapMs, nextTarget)
        } else {

            // Any other tap counts as an extra tap
            round?.extra += 1
        }
    }

    // Score the round and finish the try
    private func endRound() {
        phase = "done"
        exPhase(nil)
        guard let round else { return }
        finishTry(Train.scoreTargets(round.results, round.extra), inputType: round.inputType, path: nil, geometry: ["width": tapW, "height": tapH], results: round.results)
    }


    // RUNNING A TRY

    // The pad, drawing, buttons, scoring and result rows for this exercise
    private func exUI() -> ExUI {
        switch id {

        // Big writing on a wide pad
        case "big-writing":
            return ExUI(
                pad: "wide", guide: bigWritingGuide, overlay: loopMarks, begin: beginDrawing, score: scoreBigWritingTry,
                tooShort: Copy.tooFewLoops,
                rows: { out in
                    let m = out.measures, vs = out.vs
                    return [
                        ("size", Copy.sizeSentence(m["size"] ?? .nan, m["shrink"] ?? .nan)),
                        ("accuracy", Copy.reachedLine(m["reached"] ?? 0, m["loops"] ?? 0, m["open"] ?? 0, m["below"] ?? 0)),
                        ("pace", Copy.paceSentence(m["pace"] ?? .nan, vs.pace)),
                        ("smoothness", Copy.smoothSentence(vs.smoothness)),
                    ]
                }
            )

        // Steady tracing on a square pad
        case "steady-tracing":
            return ExUI(
                pad: "square", guide: tracingGuide, overlay: tracingOverlay, begin: beginTracing, clear: clearTracing,
                score: scoreTracingTry, tooShort: Copy.traceTooShort,
                rows: { out in
                    let m = out.measures, vs = out.vs
                    return [
                        ("accuracy", Copy.tracingAccuracy(m["accuracy"] ?? .nan, Train.traceLimit)),
                        ("coverage", Copy.tracedShare(m["cover"] ?? .nan, "spiral")),
                        ("pace", Copy.paceVs(vs.pace)),
                        ("smoothness", Copy.smoothSentence(vs.smoothness)),
                    ]
                }
            )

        // Rhythm on a wide pad
        case "rhythm":
            return ExUI(
                pad: "wide", guide: rhythmGuide, overlay: rhythmOverlay, begin: beginRhythm, start: startRhythm,
                score: scoreRhythmTry, tooShort: Copy.rhythmTooShort,
                rows: { out in
                    let m = out.measures, vs = out.vs
                    return [
                        ("timing", Copy.keptUp(m["lag"] ?? .nan, m["lead"] ?? .nan, Train.rhythmLag)),
                        ("coverage", Copy.tracedShare(m["cover"] ?? .nan, "wave")),
                        ("accuracy", Copy.waveNear(m["near"] ?? .nan, Train.rhythmNear)),
                        ("smoothness", Copy.smoothSentence(vs.smoothness)),
                    ]
                }
            )

        // Targets on the tapping area
        default:
            return ExUI(
                pad: "tap", begin: beginTargets, start: startTargets,
                rows: { out in
                    let m = out.measures
                    let caught = m["caught"] ?? 0, targets = m["targets"] ?? 0
                    return [
                        ("caught", Copy.caughtSentence(caught, targets, ceil(Train.catchShare * targets))),
                        ("reaction", Copy.reactionSentence(m["reactionMs"] ?? .nan)),
                        ("extra", Copy.extraTapsSentence(m["extraTaps"] ?? 0, floor(caught / Train.tapPrecision - caught + 1e-9))),
                    ]
                }
            )
        }
    }

    // Update the level text, the top level flag, and the hits and misses
    private func renderExProgress() {
        levelText = Copy.levelOf(state.level + 1, levels.count)
        top = state.level == levels.count - 1
        hits = state.hits
        misses = state.misses
    }

    // Clear everything from the last try and begin a new one
    func exNewTry() {

        // Stop the timers and clear the try's state
        exStop()
        phase = nil
        marks = nil
        demoAt = nil
        dotBeat = nil
        dotStart = nil
        round = nil

        // Set the pad shape, clear the pad, the status line and the result, and begin
        let ui = exUI()
        padKind = ui.pad
        exPad.reset()
        showStatus(nil)
        result = nil
        ui.begin()
    }

    // Build the result card from the outcome and any level change
    private func renderExResult(_ out: Train.Outcome, _ change: String?) {

        // The verdict is a hit, not counted when the target was reached but it wasn't a hit, or a miss
        let verdict = out.hit ? Copy.verdictHit : out.reachedTarget ? (Copy.verdictNotCounted[id] ?? "Not counted") : Copy.verdictMiss

        // When the target was reached but it wasn't a hit, add notes for slower or shakier
        let notes = out.reachedTarget && !out.hit
            ? [out.slower ? Copy.slowerNotes[id] : nil, out.shakier ? Copy.shakierNotes[id] : nil].compactMap { n in n }
            : []

        // The rows, with each key swapped for its name
        let rows = exUI().rows(out).map { (key, text) in (Copy.measureNames[key] ?? key, text) }

        // A note when the level went up or down
        var levelNote: String? = nil
        if let change {
            let levelCopy = change == "up" ? Copy.levelUp : Copy.levelDown
            levelNote = levelCopy[id]?(state.level + 1)
        }
        result = ExResult(verdict: verdict, notes: notes, rows: rows, levelNote: levelNote)
    }

    // Update the level, save the try, and show the result
    private func finishTry(_ out: Train.Outcome, inputType: String?, path: ReplayPath?, geometry: [String: Double], results: [Train.TargetResult]? = nil) {

        // Move the level up or down and save the new level state
        let before = state
        let (next, change) = Train.applyTry(before, (counted: out.counted, hit: out.hit), levels.count)
        state = next
        Store.setTrainingState(id, next)

        // Build the record of this try at the level it was done on
        let record = TrainingTry(
            id: nil,
            ts: Int(Date().timeIntervalSince1970 * 1000),
            exercise: id,
            level: before.level,
            target: levels[before.level],
            counted: true,
            hit: out.hit,
            reachedTarget: out.reachedTarget,
            slower: out.slower,
            shakier: out.shakier,
            measures: out.measures,
            vs: out.vs,
            inputType: inputType,
            path: path,
            geometry: geometry,
            results: results
        )

        // Save the try in the background, and print an error if that fails
        Task {
            do {
                _ = try await Store.saveTrainingTry(record)
            } catch {
                print("NeuroTrace: couldn't save this try", error)
            }
        }

        // Show the result, the progress and the Next try button, and scroll to the result
        renderExResult(out, change)
        renderExProgress()
        exActions("next")
        scrollToResult += 1
    }

    // Load the exercise when the screen shows, and begin a try
    func onShow(_ id: String) {

        // Stop the last exercise, and set up the sound for rhythm
        exStop()
        if id == "rhythm" { Metronome.prepare() }

        // Load the saved level state, the levels and the text for this exercise
        self.id = id
        state = Store.getTrainingState(id) ?? Train.newLevelState()
        levels = Train.exercises[id]?.levels ?? []
        title = Copy.exerciseNames[id] ?? id
        instruction = Copy.instructions[id] ?? ""
        padLabel = Copy.padLabels[id] ?? ""
        renderExProgress()
        exNewTry()
    }

    // Run the exercise's clear, or start a new try if it has none
    func clearTapped() { (exUI().clear ?? exNewTry)() }

    // Run the exercise's start, if it has one
    func startTapped() { exUI().start?() }

    // Drop down a level and start a new try
    func tooHardTapped() {
        let next = Train.tooHard(state)

        // On the lowest level, show a message and stop
        if next == state { return Motion.toast(Copy.tooHardLowest, ok: false) }

        // Save the lower level, start a new try and show which level it is
        state = next
        Store.setTrainingState(id, next)
        renderExProgress()
        exNewTry()
        Motion.toast(Copy.tooHardToast(next.level + 1))
    }

    // Score the drawing on the pad when Done is tapped
    func done() async {

        // Lock the pad and read the drawing, its stroke starts and the pad size
        doneDisabled = true
        setInert(true)
        let trace = exPad.trace()
        let starts = exPad.strokeStarts()
        let width = Double(exPad.bounds.width), height = Double(exPad.bounds.height)

        // The measures from earlier counted tries with the same kind of input
        let tries = (try? await Store.listTrainingTries(id)) ?? []
        let recent = tries.filter { t in t.counted && t.inputType == trace.inputType }.map { t in t.measures }

        // Score the drawing
        guard let score = exUI().score else { return }
        let (out, geometry) = score(trace.samples, starts, width, height, recent)

        // If it didn't count, unlock the pad and show the too short message
        if !out.counted {
            setInert(false)
            doneDisabled = !exPad.hasInk()
            return showStatus(exUI().tooShort)
        }

        // Stop everything, show the loop marks, and finish the try
        exStop()
        phase = "done"
        marks = out.marks
        exPad.redraw()
        exPhase(nil)
        finishTry(out, inputType: trace.inputType, path: replayPath(trace.samples, starts), geometry: geometry)
    }
}


// THE SCREEN

// The screen for one training exercise, with no tab bar and a back link to Training
struct ExerciseScreen: View {

    // The app model, colors and text sizes
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.exercise

        // A wider page on screens 700 points wide or more
        ScreenView(maxWidth: typo.width >= 700 ? 760 : 560) { proxy in

            // The back link and the level at the top
            Bar {
                BackLink(label: "Training") { app.go(.training) }
            } center: {
                Text(m.levelText).text(.barTitle)
            } right: {
                EmptyView()
            }

            // The title and the instruction
            H1(text: m.title)
            Text(m.instruction).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 10)

            // The progress in a row if it fits, and stacked if not
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { progress(m) }
                VStack(alignment: .leading, spacing: 6) { progress(m) }
            }
            .padding(.top, 14)

            // The phase text, with room for 1.5 lines on wide screens and 3 lines on narrow ones
            Text(m.phaseText)
                .nt(.body(nil, 600))
                .foregroundStyle(p.ink.color)
                .frame(minHeight: typo.scaled(typo.body) * (typo.width >= 700 ? 1.5 : 3), alignment: .topLeading)
                .padding(.top, 10)
                .accessibilityAddTraits(.updatesFrequently)

            // The tapping area for targets, or the drawing pad for the others
            Group {
                if m.padKind == "tap" {
                    PadBox(wide: true) { TapView(canvas: m.tapCanvas) }
                } else {
                    PadBox(wide: m.padKind == "wide") { PadView(pad: m.exPad, label: m.padLabel) }
                }
            }
            .padding(.top, 10)

            // The status line
            StatusBox(sentence: m.status, shake: m.shaker.x)

            // The result card, once a try is done
            if let r = m.result {
                Card {

                    // The verdict and the notes
                    Text(r.verdict).text(.cardTitle)
                    ForEach(0..<r.notes.count, id: \.self) { i in Text(r.notes[i]).text(.body).fixedSize(horizontal: false, vertical: true) }

                    // Each row with its name and sentence, and a thin line above it
                    ForEach(0..<r.rows.count, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.rows[i].0).text(.strong)
                            Text(r.rows[i].1).text(.sub).fixedSize(horizontal: false, vertical: true)
                        }
                        .fullWidth()
                        .padding(.top, 12)
                        .overlay(alignment: .top) { Hairline() }
                    }

                    // The level change note
                    if let note = r.levelNote { Text(note).text(.strong) }
                }
                .padding(.top, 16)
                .id("ex-result")
            }

            // Scroll to the result card when scrollToResult goes up, with no animation when Motion is set to Reduced
            Color.clear.frame(height: 0)
                .onChange(of: m.scrollToResult) { _, _ in
                    withAnimation(Motion.reduced() ? nil : .easeInOut(duration: 0.3)) { proxy.scrollTo("ex-result", anchor: nil) }
                }

            // The buttons at the bottom for this part of the try
            Spacer(minLength: 0)
            switch m.actions ?? "" {

            // Start over and Done while drawing
            case "draw":
                HStack(spacing: 12) {
                    Btn(title: "Start over", kind: .secondary) { m.clearTapped() }
                    Btn(title: "Done", disabled: m.doneDisabled) { Task { await m.done() } }
                }
                .padding(.top, 24)

            // Start before a rhythm or target round
            case "start":
                Btn(title: "Start") { m.startTapped() }.padding(.top, 24)

            // Next try after a result
            case "next":
                Btn(title: "Next try") { m.exNewTry() }.padding(.top, 24)

            // No buttons otherwise
            default:
                EmptyView()
            }

            // The Too hard today button
            Button {
                m.tooHardTapped()
            } label: {
                Text("Too hard today")
                    .nt(.body(nil, 600))
                    .foregroundStyle(p.accent.color)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .fullWidth(.center)
        }
    }

    // The progress toward the next level
    @ViewBuilder
    private func progress(_ m: ExerciseModel) -> some View {

        // At the top level, say so
        if m.top {
            Text(Copy.topLevel).text(.sub)
        } else {

            // One dot per hit needed to level up, filled in for each hit so far, hidden from screen readers
            HStack(spacing: 8) {
                ForEach(0..<Train.hitsToLevelUp, id: \.self) { i in
                    Circle().fill(i < m.hits ? p.accent.color : p.fill.color).frame(width: 14, height: 14)
                }
            }
            .accessibilityHidden(true)
            Text(Copy.hitsSoFar(m.hits, Train.hitsToLevelUp)).text(.sub)
        }

        // The misses in a row, when there are any
        if m.misses > 0 { Text(Copy.missesInARow(m.misses, Train.missesToLevelDown)).text(.sub) }
    }
}
