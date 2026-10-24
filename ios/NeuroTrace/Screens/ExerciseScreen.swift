import AVFoundation
import SwiftUI
import UIKit

private let demoSecs = 4.0, imagineSecs = 4
private let gapMs = 400.0
private let tapSlack = 6.0

struct ExResult {
    var verdict: String
    var notes: [String]
    var rows: [(String, String)]
    var levelNote: String?
}

private struct Target {
    var x: Double
    var y: Double
    var size: Double
    var at: Double
}

private struct Round {
    var results: [Train.TargetResult] = []
    var extra = 0
    var target: Target? = nil
    var pencilSeen = false
    var inputType: String? = nil
}

private struct ExUI {
    var pad: String
    var guide: PadDraw? = nil
    var overlay: PadDraw? = nil
    var begin: @MainActor () -> Void
    var clear: (@MainActor () -> Void)? = nil
    var start: (@MainActor () -> Void)? = nil
    var score: (@MainActor ([Sample], [Int], Double, Double, [[String: Double]]) -> (out: Train.Outcome, geometry: [String: Double]))? = nil
    var tooShort: String? = nil
    var rows: @MainActor (Train.Outcome) -> [(String, String)]
}

@MainActor
private final class Metronome {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let rate = 44100.0
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    var currentTime: Double { 0 }

    static func prepare() {
        DispatchQueue.global(qos: .userInitiated).async {
            try? AVAudioSession.sharedInstance().setCategory(.ambient)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    func play(_ clicks: [(at: Double, accent: Bool)]) throws {
        if !engine.isRunning { try engine.start() }
        let end = (clicks.map { c in c.at }.max() ?? 0) + 0.1
        let frames = AVAudioFrameCount(end * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        let total = Int(frames)
        for i in 0..<total { data[i] = 0 }
        for click in clicks {
            let f = click.accent ? 1320.0 : 880.0
            let first = Int(click.at * rate)
            for n in 0..<Int(0.08 * rate) where first + n < total {
                let t = Double(n) / rate
                let g = t < 0.004 ? 0.0001 * pow(0.5 / 0.0001, t / 0.004) : t < 0.07 ? 0.5 * pow(0.0001 / 0.5, (t - 0.004) / 0.066) : 0.0001
                data[first + n] += Float(g * sin(2 * Double.pi * f * t))
            }
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        player.play()
    }

    func stop() { player.stop() }
}

final class TapCanvas: UIView {
    var onTap: ((UITouch) -> Void)?
    var onResize: (() -> Void)?
    var paint: ((CGContext) -> Void)?

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

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        !(gestureRecognizer is UIPanGestureRecognizer)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        paint?(ctx)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onResize?()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { onTap?(touch) }
    }
}

private struct TapView: UIViewRepresentable {
    let canvas: TapCanvas

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .clear
        host.addSubview(canvas)
        canvas.frame = host.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return host
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if canvas.superview !== uiView {
            uiView.addSubview(canvas)
            canvas.frame = uiView.bounds
        }
    }
}



@MainActor
@Observable
final class ExerciseModel {
    unowned let app: AppModel

    var id = ""
    var title = ""
    var instruction = ""
    var padLabel = ""
    var levelText = ""
    var phaseText = ""
    var hits = 0
    var misses = 0
    var top = false
    var actions: String? = "draw"
    var padKind = "wide"
    var doneDisabled = true
    var status: String? = nil
    let shaker = Shaker()
    var result: ExResult? = nil
    var scrollToResult = 0

    @ObservationIgnored private var state = Train.newLevelState()
    @ObservationIgnored private var levels: [Double] = []
    @ObservationIgnored private var phase: String? = nil
    @ObservationIgnored private var marks: [Train.LoopMark]? = nil
    @ObservationIgnored private var demoAt: Double? = nil
    @ObservationIgnored private var dotBeat: Double? = nil
    @ObservationIgnored private var dotStart: Double? = nil
    @ObservationIgnored private var inert = false

    @ObservationIgnored private var exTimers: [Task<Void, Never>] = []
    @ObservationIgnored private var exFrame = 0
    @ObservationIgnored private var exClicks: [(at: Double, accent: Bool)] = []
    @ObservationIgnored private var audio: Metronome? = nil
    @ObservationIgnored private var round: Round? = nil
    @ObservationIgnored private var tapW = 0.0
    @ObservationIgnored private var tapH = 0.0
    @ObservationIgnored private var paintAt = 0.0
    @ObservationIgnored private var spiralCache: (path: Train.Path, w: Double, h: Double)? = nil
    @ObservationIgnored private var waveCache: (path: Train.Path, w: Double, h: Double)? = nil

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

    @ObservationIgnored lazy var tapCanvas: TapCanvas = {
        let canvas = TapCanvas(frame: .zero)
        canvas.paint = { [weak self] ctx in MainActor.assumeIsolated { self?.drawTarget(ctx) } }
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

    init(app: AppModel) { self.app = app }

    private func exTarget() -> Double { levels[state.level] }

    func exStop() {
        exTimers.forEach { t in t.cancel() }
        exTimers = []
        Frames.cancel(exFrame)
        audio?.stop()
        exClicks = []
    }

    private func exAfter(_ ms: Double, _ fn: @escaping @MainActor () -> Void) { exTimers.append(Task.after(milliseconds: ms, fn)) }

    private func exPhase(_ text: String?) { phaseText = text ?? "" }

    private func exActions(_ which: String?) { actions = which }

    private func setInert(_ on: Bool) {
        inert = on
        exPad.isUserInteractionEnabled = !on
    }

    private func onInk(_ cleared: String?) {
        doneDisabled = inert || !exPad.hasInk()
        showStatus(cleared != nil ? Copy.resizeCleared : nil)
    }

    private func showStatus(_ sentence: String?) {
        status = sentence
        guard let sentence else { return }
        shaker.shake()
        UIAccessibility.post(notification: .announcement, argument: sentence)
    }

    private func strokePath(_ ctx: CGContext, _ path: Train.Path, _ upTo: Int? = nil) {
        ctx.beginPath()
        for i in 0..<(upTo ?? path.x.count) {
            if i == 0 { ctx.move(to: CGPoint(x: path.x[i], y: path.y[i])) } else { ctx.addLine(to: CGPoint(x: path.x[i], y: path.y[i])) }
        }
        ctx.strokePath()
    }

    private func dot(_ ctx: CGContext, _ x: Double, _ y: Double, _ r: Double) {
        ctx.setFillColor(Palette.current.accent.ui.cgColor)
        ctx.beginPath()
        ctx.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
        ctx.fillPath()
    }

    private func writingGeometry(_ w: Double, _ h: Double, _ share: Double) -> (baselineY: Double, targetPx: Double, targetY: Double, left: Double, right: Double) {
        let baselineY = h * 0.8
        return (baselineY: baselineY, targetPx: h * share, targetY: baselineY - h * share, left: w * 0.06, right: w * 0.94)
    }

    private func bigWritingGuide(_ ctx: CGContext, _ cw: CGFloat, _ ch: CGFloat) {
        let g = writingGeometry(Double(cw), Double(ch), exTarget())
        ctx.saveGState()
        ctx.setLineWidth(2)
        ctx.setStrokeColor(Palette.current.guide.ui.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: g.left, y: g.baselineY))
        ctx.addLine(to: CGPoint(x: g.right, y: g.baselineY))
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [10, 8])
        ctx.setStrokeColor(Palette.current.accent.ui.cgColor)
        ctx.beginPath()
        ctx.move(to: CGPoint(x: g.left, y: g.targetY))
        ctx.addLine(to: CGPoint(x: g.right, y: g.targetY))
        ctx.strokePath()
        let font = Fonts.make(.body(15, 600), size: 15)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: Palette.current.ink2.ui]
        let label = Copy.targetLabel as NSString
        let size = label.size(withAttributes: attributes)
        UIGraphicsPushContext(ctx)
        label.draw(at: CGPoint(x: g.right - Double(size.width), y: g.targetY - 10 - Double(font.ascender)), withAttributes: attributes)
        UIGraphicsPopContext()
        ctx.restoreGState()
    }

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

    private func beginDrawing() {
        setInert(false)
        exActions("draw")
        exPhase(nil)
    }

    private func scoreBigWritingTry(_ samples: [Sample], _ starts: [Int], _ w: Double, _ h: Double, _ recent: [[String: Double]]) -> (out: Train.Outcome, geometry: [String: Double]) {
        let geo = writingGeometry(w, h, exTarget())
        return (
            out: Train.scoreBigWriting(samples, starts, (baselineY: geo.baselineY, targetPx: geo.targetPx), recent),
            geometry: ["width": w, "height": h, "baselineY": geo.baselineY, "targetPx": geo.targetPx]
        )
    }

    private func spiralFor(_ w: Double, _ h: Double) -> Train.Path {
        if spiralCache?.w != w || spiralCache?.h != h { spiralCache = (path: Train.tracingPath(w, h), w: w, h: h) }
        return spiralCache!.path
    }

    private func tracingGuide(_ ctx: CGContext, _ cw: CGFloat, _ ch: CGFloat) {
        let path = spiralFor(Double(cw), Double(ch))
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

    private func tracingOverlay(_ ctx: CGContext, _ cw: CGFloat, _ ch: CGFloat) {
        guard phase == "watch", let demoAt else { return }
        let path = spiralFor(Double(cw), Double(ch))
        let along = demoAt * path.length
        ctx.saveGState()
        ctx.setStrokeColor(Palette.current.accent.ui.cgColor)
        ctx.setLineWidth(max(3, cw / 110))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let upTo = path.s.firstIndex { s in s > along }
        strokePath(ctx, path, upTo ?? path.x.count)
        ctx.restoreGState()
        let (x, y) = Train.pointAlong(path, along)
        dot(ctx, x, y, 9)
    }

    private func beginTracing() {
        phase = "watch"
        setInert(true)
        exActions("draw")
        doneDisabled = true
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
        if Motion.reduced() {
            exPhase(Copy.look)
            exPad.redraw()
            return exAfter(2500, imagine)
        }
        exPhase(Copy.watch)
        let t0 = Frames.now()
        func step(_ now: Double) {
            demoAt = min(1, (now - t0) / 1000 / demoSecs)
            exPad.redraw()
            if (demoAt ?? 1) < 1 { exFrame = Frames.next(step) } else { exAfter(600, imagine) }
        }
        exFrame = Frames.next(step)
    }

    private func clearTracing() {
        if phase != "trace" { return exNewTry() }
        exPad.reset()
        setInert(false)
        doneDisabled = true
        showStatus(nil)
    }

    private func scoreTracingTry(_ samples: [Sample], _ starts: [Int], _ w: Double, _ h: Double, _ recent: [[String: Double]]) -> (out: Train.Outcome, geometry: [String: Double]) {
        let path = spiralFor(w, h)
        return (
            out: Train.scoreTracing(samples, starts, path, recent),
            geometry: ["width": w, "height": h, "radius": path.radius, "visibility": exTarget()]
        )
    }

    private func waveFor(_ w: Double, _ h: Double) -> Train.Path {
        if waveCache?.w != w || waveCache?.h != h { waveCache = (path: Train.rhythmPath(w, h), w: w, h: h) }
        return waveCache!.path
    }

    private func rhythmGuide(_ ctx: CGContext, _ cw: CGFloat, _ ch: CGFloat) {
        ctx.saveGState()
        ctx.setStrokeColor(Palette.current.guide.ui.cgColor)
        ctx.setLineWidth(max(2, cw / 180))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        strokePath(ctx, waveFor(Double(cw), Double(ch)))
        ctx.restoreGState()
    }

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

    private func beginRhythm() {
        phase = "ready"
        dotBeat = 0
        setInert(true)
        exActions("start")
        exPhase(Copy.rhythmReady)
        exPad.redraw()
    }

    private func click(_ at: Double, _ accent: Bool) {
        exClicks.append((at: at, accent: accent))
    }

    private func startRhythm() {
        let beatSec = 60 / exTarget()
        let lead = 0.15
        do {
            if audio == nil { audio = Metronome() }
            let t0 = (audio?.currentTime ?? 0) + lead
            for k in 0...Int(Train.countIn + Train.rhythmBeats) { click(t0 + Double(k) * beatSec, Double(k) == Train.countIn) }
            try audio?.play(exClicks)
        } catch {
            print("NeuroTrace: no metronome sound", error)
        }
        dotStart = Frames.now() + (lead + Train.countIn * beatSec) * 1000
        phase = "count"
        setInert(false)
        exActions("draw")
        doneDisabled = !exPad.hasInk()
        func step(_ now: Double) {
            let t = (now - (dotStart ?? now)) / 1000
            if t < 0 { exPhase(Copy.getReady(Int(min(Train.countIn, ceil(-t / beatSec))))) }
            else if phase == "count" {
                phase = "run"
                exPhase(Copy.follow)
            }
            dotBeat = min(Train.rhythmBeats, max(0, t / beatSec))
            exPad.redraw()
            if t < Train.rhythmBeats * beatSec { exFrame = Frames.next(step) }
            else {
                phase = "end"
                exPhase(Copy.rhythmEnd)
            }
        }
        exFrame = Frames.next(step)
    }

    private func scoreRhythmTry(_ samples: [Sample], _ starts: [Int], _ w: Double, _ h: Double, _ recent: [[String: Double]]) -> (out: Train.Outcome, geometry: [String: Double]) {
        let beatSec = 60 / exTarget()
        let first = exPad.startedAt()
        let penOffset = dotStart != nil && first != nil ? (first! - dotStart!) / 1000 : 0
        return (
            out: Train.scoreRhythm(samples, starts, waveFor(w, h), (beatSec: beatSec, penOffset: penOffset), recent),
            geometry: ["width": w, "height": h, "bpm": exTarget(), "penOffset": penOffset]
        )
    }

    private func sizeTapCanvas() {
        tapW = Double(tapCanvas.bounds.width)
        tapH = Double(tapCanvas.bounds.height)
    }

    private func paintTarget(_ now: Double = Frames.now()) {
        paintAt = now
        tapCanvas.setNeedsDisplay()
    }

    private func drawTarget(_ ctx: CGContext) {
        ctx.clear(CGRect(x: 0, y: 0, width: tapW, height: tapH))
        guard let t = round?.target else { return }
        let r = Train.targetRadius(t.size, (paintAt - t.at) / 1000)
        if r > 0 { dot(ctx, t.x, t.y, r) }
    }

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

    private func startTargets() {
        phase = "run"
        exActions(nil)
        round = Round()
        sizeTapCanvas()
        exAfter(600, nextTarget)
    }

    private func nextTarget() {
        guard round != nil else { return }
        if (round?.results.count ?? 0) >= Train.targets { return endRound() }
        let size = exTarget(), m = size / 2 + 8
        round?.target = Target(x: m + Double.random(in: 0..<1) * (tapW - 2 * m), y: m + Double.random(in: 0..<1) * (tapH - 2 * m), size: size, at: Frames.now())
        exPhase(Copy.circleOf((round?.results.count ?? 0) + 1, Train.targets))
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

    private func tapped(_ e: UITouch) {
        if phase != "run" || round == nil { return }
        let kind = InputKind(e)
        if kind == .pencil { round?.pencilSeen = true }
        if kind == .touch && round?.pencilSeen == true { return }
        if round?.inputType == nil { round?.inputType = kind.rawValue }
        let t = round?.target
        let point = e.location(in: tapCanvas)
        let x = Double(point.x), y = Double(point.y)
        let stamp = e.timestamp * 1000
        let r = t.map { t in Train.targetRadius(t.size, (stamp - t.at) / 1000) } ?? 0
        if let t, r > 0 && hypot(x - t.x, y - t.y) <= r + tapSlack {
            round?.results.append(Train.TargetResult(caught: true, ms: jsRound(stamp - t.at)))
            round?.target = nil
            Frames.cancel(exFrame)
            paintTarget()
            vibrate(10)
            exAfter(gapMs, nextTarget)
        } else {
            round?.extra += 1
        }
    }

    private func endRound() {
        phase = "done"
        exPhase(nil)
        guard let round else { return }
        finishTry(Train.scoreTargets(round.results, round.extra), inputType: round.inputType, path: nil, geometry: ["width": tapW, "height": tapH], results: round.results)
    }

    private func exUI() -> ExUI {
        switch id {
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

    private func renderExProgress() {
        levelText = Copy.levelOf(state.level + 1, levels.count)
        top = state.level == levels.count - 1
        hits = state.hits
        misses = state.misses
    }

    func exNewTry() {
        exStop()
        phase = nil
        marks = nil
        demoAt = nil
        dotBeat = nil
        dotStart = nil
        round = nil
        let ui = exUI()
        padKind = ui.pad
        exPad.reset()
        showStatus(nil)
        result = nil
        ui.begin()
    }

    private func renderExResult(_ out: Train.Outcome, _ change: String?) {
        let verdict = out.hit ? Copy.verdictHit : out.reachedTarget ? (Copy.verdictNotCounted[id] ?? "Not counted") : Copy.verdictMiss
        let notes = out.reachedTarget && !out.hit
            ? [out.slower ? Copy.slowerNotes[id] : nil, out.shakier ? Copy.shakierNotes[id] : nil].compactMap { n in n }
            : []
        let rows = exUI().rows(out).map { (key, text) in (Copy.measureNames[key] ?? key, text) }
        var levelNote: String? = nil
        if let change {
            let levelCopy = change == "up" ? Copy.levelUp : Copy.levelDown
            levelNote = levelCopy[id]?(state.level + 1)
        }
        result = ExResult(verdict: verdict, notes: notes, rows: rows, levelNote: levelNote)
    }

    private func finishTry(_ out: Train.Outcome, inputType: String?, path: ReplayPath?, geometry: [String: Double], results: [Train.TargetResult]? = nil) {
        let before = state
        let (next, change) = Train.applyTry(before, (counted: out.counted, hit: out.hit), levels.count)
        state = next
        Store.setTrainingState(id, next)
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
        Task {
            do {
                _ = try await Store.saveTrainingTry(record)
            } catch {
                print("NeuroTrace: couldn't save this try", error)
            }
        }
        renderExResult(out, change)
        renderExProgress()
        exActions("next")
        scrollToResult += 1
    }

    func onShow(_ id: String) {
        exStop()
        if id == "rhythm" { Metronome.prepare() }
        self.id = id
        state = Store.getTrainingState(id) ?? Train.newLevelState()
        levels = Train.exercises[id]?.levels ?? []
        title = Copy.exerciseNames[id] ?? id
        instruction = Copy.instructions[id] ?? ""
        padLabel = Copy.padLabels[id] ?? ""
        renderExProgress()
        exNewTry()
    }

    func clearTapped() { (exUI().clear ?? exNewTry)() }

    func startTapped() { exUI().start?() }

    func tooHardTapped() {
        let next = Train.tooHard(state)
        // Level 1 has nothing easier, so say so instead of doing nothing
        if next == state { return Motion.toast(Copy.tooHardLowest, ok: false) }
        state = next
        Store.setTrainingState(id, next)
        renderExProgress()
        exNewTry()
        Motion.toast(Copy.tooHardToast(next.level + 1))
    }

    func done() async {
        doneDisabled = true
        setInert(true)
        let trace = exPad.trace()
        let starts = exPad.strokeStarts()
        let width = Double(exPad.bounds.width), height = Double(exPad.bounds.height)
        let tries = (try? await Store.listTrainingTries(id)) ?? []
        let recent = tries.filter { t in t.counted && t.inputType == trace.inputType }.map { t in t.measures }
        guard let score = exUI().score else { return }
        let (out, geometry) = score(trace.samples, starts, width, height, recent)
        if !out.counted {
            setInert(false)
            doneDisabled = !exPad.hasInk()
            return showStatus(exUI().tooShort)
        }
        exStop()
        phase = "done"
        marks = out.marks
        exPad.redraw()
        exPhase(nil)
        finishTry(out, inputType: trace.inputType, path: replayPath(trace.samples, starts), geometry: geometry)
    }
}

// one training exercise. no tab bar: it's a focused
// task with its own way back to Training.
struct ExerciseScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.exercise
        ScreenView(maxWidth: typo.width >= 700 ? 760 : 560) { proxy in
            Bar {
                BackLink(label: "Training") { app.go(.training) }
            } center: {
                Text(m.levelText).text(.barTitle)
            } right: {
                EmptyView()
            }

            H1(text: m.title)
            Text(m.instruction).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 10)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { progress(m) }
                VStack(alignment: .leading, spacing: 6) { progress(m) }
            }
            .padding(.top, 14)

            Text(m.phaseText)
                .nt(.body(nil, 600))
                .foregroundStyle(p.ink.color)
                .frame(minHeight: typo.scaled(typo.body) * (typo.width >= 700 ? 1.5 : 3), alignment: .topLeading)
                .padding(.top, 10)
                .accessibilityAddTraits(.updatesFrequently)

            Group {
                if m.padKind == "tap" {
                    PadBox(wide: true) { TapView(canvas: m.tapCanvas) }
                } else {
                    PadBox(wide: m.padKind == "wide") { PadView(pad: m.exPad, label: m.padLabel) }
                }
            }
            .padding(.top, 10)

            StatusBox(sentence: m.status, shake: m.shaker.x)

            if let r = m.result {
                Card {
                    Text(r.verdict).text(.cardTitle)
                    ForEach(0..<r.notes.count, id: \.self) { i in Text(r.notes[i]).text(.body).fixedSize(horizontal: false, vertical: true) }
                    ForEach(0..<r.rows.count, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.rows[i].0).text(.strong)
                            Text(r.rows[i].1).text(.sub).fixedSize(horizontal: false, vertical: true)
                        }
                        .fullWidth()
                        .padding(.top, 12)
                        .overlay(alignment: .top) { Hairline() }
                    }
                    if let note = r.levelNote { Text(note).text(.strong) }
                }
                .padding(.top, 16)
                .id("ex-result")
            }
            Color.clear.frame(height: 0)
                .onChange(of: m.scrollToResult) { _, _ in
                    withAnimation(Motion.reduced() ? nil : .easeInOut(duration: 0.3)) { proxy.scrollTo("ex-result", anchor: nil) }
                }

            Spacer(minLength: 0)
            switch m.actions ?? "" {
            case "draw":
                HStack(spacing: 12) {
                    Btn(title: "Start over", kind: .secondary) { m.clearTapped() }
                    Btn(title: "Done", disabled: m.doneDisabled) { Task { await m.done() } }
                }
                .padding(.top, 24)
            case "start":
                Btn(title: "Start") { m.startTapped() }.padding(.top, 24)
            case "next":
                Btn(title: "Next try") { m.exNewTry() }.padding(.top, 24)
            default:
                EmptyView()
            }
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

    @ViewBuilder
    private func progress(_ m: ExerciseModel) -> some View {
        if m.top {
            Text(Copy.topLevel).text(.sub)
        } else {
            HStack(spacing: 8) {
                ForEach(0..<Train.hitsToLevelUp, id: \.self) { i in
                    Circle().fill(i < m.hits ? p.accent.color : p.fill.color).frame(width: 14, height: 14)
                }
            }
            .accessibilityHidden(true)
            Text(Copy.hitsSoFar(m.hits, Train.hitsToLevelUp)).text(.sub)
        }
        if m.misses > 0 { Text(Copy.missesInARow(m.misses, Train.missesToLevelDown)).text(.sub) }
    }
}
