// DRAWSCREEN.SWIFT IS THE SCREEN WHERE PEOPLE TRACE THREE SPIRALS FOR A CHECK IN
// IT MEASURES EACH SPIRAL, SCORES THE CHECK IN, SAVES IT, AND OPENS THE RESULTS

import SwiftUI
import UIKit

// One spiral from the check in, with its strokes and measurements
private struct CheckinTrial {
    var trace: Trace
    var strokeStarts: [Int]
    var features: [String: Double]
}

// Holds what the drawing screen needs, and handles each spiral and the finished check in
@MainActor
@Observable
final class DrawModel {

    // The main app model
    unowned let app: AppModel

    // How many spirals a check in has
    static let checkinTrials = 3

    // The spirals drawn so far
    private var trials: [CheckinTrial] = []

    // The spiral count text, how many spirals are done, and a number that goes up for each new spiral
    var count = "Spiral 1 of 1"
    var progressDone = 0
    var trialID = 0

    // Whether Done is off, the message under the pad, and the shake for that message
    var doneDisabled = true
    var status: String? = nil
    let shaker = Shaker()

    // True while the pad fades out between spirals
    var wiping = false

    // True once the last spiral is in and the check in is being scored and saved
    var finishing = false

    // True while the pad ignores touches
    @ObservationIgnored private var inert = false

    // How many times SpiralCheck has sent back the spiral being drawn now
    @ObservationIgnored private var redos = 0

    // The drawing pad, made the first time it is used, with the pen tip glow added
    @ObservationIgnored lazy var pad: Pad = {
        let made = createPad(onInk: { [weak self] cleared in self?.onInk(cleared) })
        attachPenTip(to: made)
        return made
    }()

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // Runs when ink changes on the pad
    // Turns Done on when there is ink, and shows a message and the start dot if the pad was cleared
    private func onInk(_ cleared: String?) {
        doneDisabled = inert || !pad.hasInk()
        showStatus(cleared != nil ? Copy.resizeCleared : nil)
        if cleared != nil { pad.showStartDot(true) }
    }

    // Turns touches on the pad off or on
    private func setInert(_ on: Bool) {
        inert = on
        pad.isUserInteractionEnabled = !on
    }

    // Shows a message under the pad, shakes it, and reads it out to screen reader users
    func showStatus(_ sentence: String?) {
        status = sentence
        guard let sentence else { return }
        shaker.shake()
        UIAccessibility.post(notification: .announcement, argument: sentence)
    }

    // Gets the screen ready for the next spiral
    func newTrial() {

        // Update the spiral count and the progress bar
        count = "Spiral \(trials.count + 1) of \(DrawModel.checkinTrials)"
        progressDone = trials.count
        trialID += 1
        redos = 0

        // Clear the pad, show the start dot, and turn touches back on
        pad.reset()
        pad.showStartDot(true)
        setInert(false)
        doneDisabled = true
        showStatus(nil)
    }

    // Starts a fresh check in when the screen shows
    func onShow() {
        trials = []
        finishing = false
        newTrial()
    }

    // Runs when Done is tapped
    // Measures and checks the spiral, then starts the next one or scores and saves the check in
    func done() async {

        // Do nothing if the pad is resting or Done is off
        if inert || doneDisabled { return }
        guard let choice = app.choice else { return }

        // Read the spiral and its strokes off the pad
        let trace = pad.trace(choice.hand)
        let starts = pad.strokeStarts()
        let trial = trialID

        // Turn the pad off and measure the spiral in the background
        setInert(true)
        doneDisabled = true
        let measured = try? await JSCore.background { try NTFeatures.featuresFromTrace(trace) }

        // Stop if a new spiral was started or the screen changed while measuring
        if trialID != trial || app.screen != .draw { return }

        // If it couldn't be measured, turn the pad back on and say the spiral was too short
        guard let features = measured else {
            setInert(false)
            doneDisabled = !pad.hasInk()
            return showStatus(Copy.tooShort)
        }

        // If SpiralCheck finds a problem, clear the pad and show a message about it
        // After a few tries it shows a different message
        if let problem = SpiralCheck.problem(features) {
            redos += 1
            setInert(false)
            pad.reset()
            pad.showStartDot(true)
            doneDisabled = true
            return showStatus(redos > SpiralCheck.hintAfter ? Copy.spiralStillOff : problem == .offGuide ? Copy.spiralOffGuide : Copy.spiralTooFast)
        }

        // Keep the spiral and give a short buzz
        trials.append(CheckinTrial(trace: trace, strokeStarts: starts, features: features))
        vibrate(12)

        // If more spirals are needed, show a toast, fade the pad, and start the next one
        if trials.count < DrawModel.checkinTrials {
            Motion.toast(Copy.spiralSaved(trials.count))
            wipe()
            Task.after(milliseconds: Motion.reduced() ? 0 : 160) { self.newTrial() }
            return
        }

        // Show the measuring screen and wait for the scoring files
        finishing = true
        let finish = Motion.measuring()

        // If the scoring files can't load, go to the error screen
        guard let scoring = try? await app.scoring.value else {
            let hide = await finish()
            app.go(.error)
            hide?()
            return
        }

        // Score the three spirals and build the check in record
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

        // Save the check in to history, and print the error if it can't be saved
        do {
            _ = try await Store.saveAssessment(record)
        } catch {
            print("NeuroTrace: couldn't save this check-in to history", error)
        }

        // Hide the measuring screen and open the results
        let hide = await finish()
        app.current = record
        app.go(.results)
        hide?()
    }

    // Fades the pad out and back in over 160 milliseconds each way, unless Reduced Motion is on
    private func wipe() {
        if Motion.reduced() { return }
        withAnimation(Theme.ease(160)) { wiping = true }
        Task.after(milliseconds: 160) {
            withAnimation(Theme.ease(160)) { self.wiping = false }
        }
    }
}


// A soft glowing circle that follows the finger or pencil on the pad
private final class PenTip: UIView {

    // The round glow
    private let glow = CAGradientLayer()

    // Whether the glow shows, fading in or out when it changes
    var on = false {
        didSet {
            UIView.animate(withDuration: Motion.reduced() ? 0 : 0.18) { self.alpha = self.on ? 1 : 0 }
        }
    }

    // Set up a hidden round glow that ignores touches, and recolor it when the colors change
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

    // Stops the app if the view is loaded from a storyboard
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // Make the glow fill the view
    override func layoutSubviews() {
        super.layoutSubviews()
        glow.frame = bounds
    }

    // Color the glow with the accent color, fading from the middle out to clear
    @objc private func recolor() {
        glow.colors = [Palette.current.accent.ui.withAlphaComponent(0.38).cgColor, Palette.current.accent.ui.withAlphaComponent(0).cgColor]
    }
}


// Adds the pen tip glow to the pad and moves it with each touch
@MainActor
private func attachPenTip(to pad: Pad) {
    let penTip = PenTip(frame: CGRect(x: 0, y: 0, width: 48, height: 48))
    pad.addSubview(penTip)
    let movePenTip = { (touch: UITouch) in penTip.center = touch.location(in: pad) }

    // Show the glow when a touch starts, move it with the touch, and hide it when the touch ends
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


// The drawing screen itself
struct DrawScreen: View {

    // The app model and the text sizes
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.draw
        ScreenView(maxWidth: typo.width >= 700 ? 760 : 560) { _ in

            // The top bar with Cancel and the spiral count
            Bar {
                BarLink(label: "Cancel") { app.go(.testing) }
            } center: {
                Text(m.count).text(.barTitle)
            } right: {
                EmptyView()
            }

            // The progress bar, one segment per spiral
            Segments(total: DrawModel.checkinTrials, done: m.progressDone, width: 96)
                .id(m.trialID)
                .padding(.top, 4)
                .fullWidth(.center)

            // The title and what to do
            H1(text: "Trace the spiral", size: 28, lineHeight: 1.14, top: 20)
            Text(Copy.drawInstruction(app.choice?.hand)).text(.lede).padding(.top, 8)

            // The drawing pad, which fades and shrinks a little between spirals
            PadBox {
                PadView(pad: m.pad)
            }
            .opacity(m.wiping ? 0 : 1)
            .scaleEffect(m.wiping ? 0.96 : 1)
            .padding(.top, 20)

            // The message under the pad
            StatusBox(sentence: m.status, shake: m.shaker.x)

            // The Start over and Done buttons at the bottom
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Btn(title: "Start over", kind: .secondary, disabled: m.finishing) { m.newTrial() }
                Btn(title: "Done", disabled: m.doneDisabled) { Task { await m.done() } }
            }
            .padding(.top, 24)
        }
    }
}
