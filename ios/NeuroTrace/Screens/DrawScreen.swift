import SwiftUI
import UIKit

private struct CheckinTrial {
    var trace: Trace
    var strokeStarts: [Int]
    var features: [String: Double]
}

@MainActor
@Observable
final class DrawModel {
    unowned let app: AppModel
    static let checkinTrials = 3

    private var trials: [CheckinTrial] = []
    var count = "Spiral 1 of 1"
    var progressDone = 0
    var trialID = 0
    var doneDisabled = true
    var status: String? = nil
    let shaker = Shaker()
    var wiping = false
    // True once the last spiral is in and the check-in is being scored and saved
    var finishing = false
    @ObservationIgnored private var inert = false
    // How many times the spiral being drawn now has been sent back by SpiralCheck
    @ObservationIgnored private var redos = 0

    @ObservationIgnored lazy var pad: Pad = {
        let made = createPad(onInk: { [weak self] cleared in self?.onInk(cleared) })
        attachPenTip(to: made)
        return made
    }()

    init(app: AppModel) { self.app = app }

    private func onInk(_ cleared: String?) {
        doneDisabled = inert || !pad.hasInk()
        showStatus(cleared != nil ? Copy.resizeCleared : nil)
        if cleared != nil { pad.showStartDot(true) }
    }

    private func setInert(_ on: Bool) {
        inert = on
        pad.isUserInteractionEnabled = !on
    }

    func showStatus(_ sentence: String?) {
        status = sentence
        guard let sentence else { return }
        shaker.shake()
        UIAccessibility.post(notification: .announcement, argument: sentence)
    }

    func newTrial() {
        count = "Spiral \(trials.count + 1) of \(DrawModel.checkinTrials)"
        progressDone = trials.count
        trialID += 1
        redos = 0
        pad.reset()
        pad.showStartDot(true)
        setInert(false)
        doneDisabled = true
        showStatus(nil)
    }

    func onShow() {
        trials = []
        finishing = false
        newTrial()
    }

    func done() async {
        // A second tap on Done before the screen catches up does nothing, so one spiral can't count twice
        if inert || doneDisabled { return }
        guard let choice = app.choice else { return }
        let trace = pad.trace(choice.hand)
        let starts = pad.strokeStarts()
        let trial = trialID
        // The pad rests while the spiral is measured, and the screen keeps moving
        setInert(true)
        doneDisabled = true
        let measured = try? await JSCore.background { try NTFeatures.featuresFromTrace(trace) }
        // Start over or Cancel while it was being measured means this spiral doesn't count
        if trialID != trial || app.screen != .draw { return }
        guard let features = measured else {
            setInert(false)
            doneDisabled = !pad.hasInk()
            return showStatus(Copy.tooShort)
        }
        if let problem = SpiralCheck.problem(features) {
            redos += 1
            setInert(false)
            pad.reset()
            pad.showStartDot(true)
            doneDisabled = true
            return showStatus(redos > SpiralCheck.hintAfter ? Copy.spiralStillOff : problem == .offGuide ? Copy.spiralOffGuide : Copy.spiralTooFast)
            // Clear it and ask again. The message stays up until they start drawing, because the
            // pad only clears the status when a new stroke begins
        }
        trials.append(CheckinTrial(trace: trace, strokeStarts: starts, features: features))
        vibrate(12)
        if trials.count < DrawModel.checkinTrials {
            Motion.toast(Copy.spiralSaved(trials.count))
            wipe()
            Task.after(milliseconds: Motion.reduced() ? 0 : 160) { self.newTrial() }
            return
        }

        finishing = true
        let finish = Motion.measuring()
        guard let scoring = try? await app.scoring.value else {
            let hide = await finish()
            app.go(.error)
            hide?()
            return
        }
        let result = Score.scoreSession(trials.map { t in t.features }, scoring.model, scoring.reference, choice.bracket)
        let record = AssessmentRecord(
            ts: Int(Date().timeIntervalSince1970 * 1000),
            task: "spiral",
            hand: choice.hand,
            ageChoice: choice.ageChoice,
            bracketChoice: choice.bracket,
            inputType: trials[0].trace.inputType,
            deviceLabel: trials[0].trace.deviceLabel,
            trials: trials.map { t in
                AssessmentTrial(samples: t.trace.samples, strokeStarts: t.strokeStarts, features: t.features, path: replayPath(t.trace.samples, t.strokeStarts))
            },
            features: result.features,
            result: result
        )
        do {
            _ = try await Store.saveAssessment(record)
        } catch {
            print("NeuroTrace: couldn't save this check-in to history", error)
        }
        let hide = await finish()
        app.current = record
        app.go(.results)
        hide?()
    }

    private func wipe() {
        if Motion.reduced() { return }
        withAnimation(Theme.ease(160)) { wiping = true }
        Task.after(milliseconds: 160) {
            withAnimation(Theme.ease(160)) { self.wiping = false }
        }
    }
}

private final class PenTip: UIView {
    private let glow = CAGradientLayer()

    var on = false {
        didSet {
            UIView.animate(withDuration: Motion.reduced() ? 0 : 0.18) { self.alpha = self.on ? 1 : 0 }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.locations = [0, 0.99]
        layer.addSublayer(glow)
        recolor()
        NotificationCenter.default.addObserver(self, selector: #selector(recolor), name: .paletteChanged, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        glow.frame = bounds
    }

    @objc private func recolor() {
        glow.colors = [Palette.current.accent.ui.withAlphaComponent(0.38).cgColor, Palette.current.accent.ui.withAlphaComponent(0).cgColor]
    }
}

@MainActor
private func attachPenTip(to pad: Pad) {
    let penTip = PenTip(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
    pad.addSubview(penTip)
    let movePenTip = { (touch: UITouch) in penTip.center = touch.location(in: pad) }
    pad.onPointer = { touch, phase in
        switch phase {
        case .began:
            movePenTip(touch)
            penTip.on = true
        case .moved:
            movePenTip(touch)
        default:
            penTip.on = false
        }
    }
}

struct DrawScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.draw
        ScreenView(maxWidth: typo.width >= 700 ? 760 : 560) { _ in
            Bar {
                BarLink(label: "Cancel") { app.go(.testing) }
            } center: {
                Text(m.count).text(.barTitle)
            } right: {
                EmptyView()
            }
            Segments(total: DrawModel.checkinTrials, done: m.progressDone, width: 96)
                .id(m.trialID)
                .padding(.top, 4)
                .fullWidth(.center)

            H1(text: "Trace the spiral", size: 28, lineHeight: 1.14, top: 20)
            Text(Copy.drawInstruction(app.choice?.hand)).text(.lede).padding(.top, 8)

            PadBox {
                PadView(pad: m.pad)
            }
            .opacity(m.wiping ? 0 : 1)
            .scaleEffect(m.wiping ? 0.96 : 1)
            .padding(.top, 20)

            StatusBox(sentence: m.status, shake: m.shaker.x)

            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Btn(title: "Start over", kind: .secondary, disabled: m.finishing) { m.newTrial() }
                Btn(title: "Done", disabled: m.doneDisabled) { Task { await m.done() } }
            }
            .padding(.top, 24)
        }
    }
}
