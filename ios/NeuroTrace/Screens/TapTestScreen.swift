// TAPTESTSCREEN.SWIFT RUNS THE FINGER TAPPING TEST WITH THE FRONT CAMERA
// IT COUNTS DOWN, COUNTS TAPS FOR UP TO 15 SECONDS, SAVES THE RESULT AND SHOWS IT WITH A CHART

import Charts
import SwiftUI
import UIKit

// Vision's left or right guesses, newest last, kept in a class
private final class HandGuesses {

    // The last 30 guesses, for the hint while getting ready, with "" for a frame with no guess
    var recent: [String] = []

    // Every guess during the test itself
    var test: [String] = []
}


// The note for iPads too old for Apple's hand tracking, on the Testing card and before a test
struct OldIPadNote: View {

    // The colors
    @Environment(\.palette) private var p

    var body: some View {

        // An info icon next to a title and a line of text, read as one item by screen readers
        HStack(alignment: .top, spacing: 10) {
            IconView(icon: .info, size: 20).foregroundStyle(p.accent.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(Copy.tapOldIPadTitle).text(.strong).fixedSize(horizontal: false, vertical: true)
                Text(Copy.tapOldIPad).text(.sub).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}


// The finger tapping screen, shown full screen from the Testing tab's card
struct TapTestScreen: View {

    // What to run when the screen closes
    let close: () -> Void

    // The colors and text sizes
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    // The camera, the hand picked, and which part of the test is showing
    @State private var camera: HandCamera?
    @State private var hand = Store.getPrefs().hand
    @State private var phase = Phase.setup

    // Whether the camera sees a hand, the samples recorded, and the tap count so far
    @State private var handFound = false
    @State private var samples: [TapSample] = []
    @State private var count = 0

    // The result of the last test
    @State private var result: TapResult?

    // The hand the result is for
    @State private var testedHand = "right"

    // The sentences shown with the result
    @State private var sentences: [String] = []

    // Whether the screen is on show
    @State private var shown = false

    // The left or right guesses from the camera
    @State private var guesses = HandGuesses()

    // The hand the camera sees right now, or nil when it can't tell
    @State private var seenNow: String?

    // The other hand, set when the test used the other hand and the result was not saved
    @State private var otherHand: String?

    // The parts of the test, where noCamera is a refused permission and noFrontCamera is a device without a front camera
    enum Phase: Equatable { case setup, countdown(Int), running, done, noCamera, noFrontCamera }

    // The test stops at 10 taps or 15 seconds
    static let maxTaps = 10
    static let maxSeconds = 15.0

    // The fewest camera frames a second for a test to be kept
    static let minFps = 12.0

    var body: some View {
        ScreenView { _ in

            // The back link and the title
            BackLink(label: "Testing") { close() }
            H1(text: "Finger tapping")

            // Show a different view for each part of the test
            switch phase {

            // Camera permission refused, with a button that opens Settings
            case .noCamera:
                Text(Copy.tapNoCamera).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                Btn(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .padding(.top, 24)

            // No front camera, with a button back to Testing
            case .noFrontCamera:
                Text(Copy.tapNoFrontCamera).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                Btn(title: "Back to Testing", kind: .secondary) { close() }.padding(.top, 24)

            // The results once the test is done
            case .done:
                results

            // The camera view for setup, countdown and the test
            default:
                live
            }
        }
        .background(p.bg.color.ignoresSafeArea())
        // Open the camera when the screen shows
        .onAppear { Task { await open() } }
        // Clear the frame handler, stop the camera and let go of it when the screen closes
        .onDisappear {
            shown = false
            camera?.onFrame = { _, _, _ in }
            camera?.stop()
            camera = nil
        }
    }

    // The camera view with the hand picker and the Start button
    private var live: some View {
        VStack(alignment: .leading, spacing: 16) {

            // The tips before the test, or the go line during it
            Text(phase == .running ? Copy.tapGo : Copy.tapTips).text(.lede).fixedSize(horizontal: false, vertical: true)

            // The old iPad note during setup on devices too old for hand tracking
            if phase == .setup && !HandTracking.newEnoughHere { OldIPadNote() }

            // The left and right hand picker, faded and locked once the test starts
            Segmented(options: [("left", "Left hand"), ("right", "Right hand")], selected: hand) { value, _ in
                if phase == .setup { hand = value }
            }
            .opacity(phase == .setup ? 1 : 0.45)
            .allowsHitTesting(phase == .setup)

            // The camera preview with the status in a pill at the bottom
            ZStack(alignment: .bottom) {
                p.fill.color
                if let camera { CameraPreview(camera: camera) }
                Text(status)
                    .text(.strong)
                    .monospacedDigit()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(p.surface.color))
                    .padding(16)
            }
            // Make the preview 220 to 380 points tall based on the screen's height
            .frame(height: min(380, max(220, typo.height * 0.42)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Camera view. \(status)")

            // A line about the video staying on the device
            Text(Copy.tapOnDevice).text(.sub).fixedSize(horizontal: false, vertical: true)

            // The Start button during setup, turned off until the camera is open
            if phase == .setup {
                Btn(title: "Start", disabled: camera == nil) { Task { await run() } }
            }
        }
        .padding(.top, 12)
    }

    // The text in the pill over the camera preview
    private var status: String {
        switch phase {

        // The countdown number
        case let .countdown(n): return "\(n)"

        // The tap count during the test
        case .running: return "\(count) \(count == 1 ? "tap" : "taps")"

        // During setup, say if the camera sees the other hand, or whether it found a hand
        default:
            if let seen = seenNow, seen != hand { return Copy.tapLooksLike(seen) }
            return handFound ? "Hand found" : "Show your \(hand) hand to the camera"
        }
    }

    // The results view
    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {

            // The hand tested and the result sentences
            Text(testedHand == "left" ? "Left hand" : "Right hand").text(.sub)
            ForEach(sentences, id: \.self) { Text($0).text(.body).fixedSize(horizontal: false, vertical: true) }

            // A chart of how far the fingers opened at each tap, for a counted result with at least 2 openings
            if let r = result, r.counted, r.openings.count >= 2 {
                Card {
                    Text("Finger opening at each tap").text(.cardTitle)
                    Chart(Array(zip(r.tapTimes, r.openings).enumerated()), id: \.offset) { item in
                        LineMark(x: .value("Seconds", item.element.0), y: .value("Opening", item.element.1))
                        PointMark(x: .value("Seconds", item.element.0), y: .value("Opening", item.element.1))
                    }
                    .foregroundStyle(p.accent.color)
                    .chartXAxisLabel("Seconds")
                    .frame(height: 180)
                    .accessibilityLabel(Copy.tapChartLabel(r))
                }
                .padding(.top, 8)
            }

            // A line that says the test is not a diagnosis
            Text(Copy.tapNotDiagnosis).text(.sub).fixedSize(horizontal: false, vertical: true)

            // If the other hand was used, offer to switch hands or try again with the same hand
            if let other = otherHand {
                Btn(title: "Switch to \(other) hand and try again") { again(other) }
                    .padding(.top, 12)
                Btn(title: "Try again with \(testedHand) hand", kind: .secondary) { again(testedHand) }
            } else if result?.counted == true {

                // If the result counted, offer the other hand next
                Btn(title: "Now the other hand") { again(testedHand == "left" ? "right" : "left") }
                    .padding(.top, 12)
            } else {

                // Otherwise offer to try again
                Btn(title: "Try again") { again(testedHand) }
                    .padding(.top, 12)
            }

            // The Done button
            Btn(title: "Done", kind: .secondary) { close() }
        }
        .padding(.top, 16)
    }

    // Ask for the camera and start it
    private func open() async {

        // Mark the screen as shown, and stop if a camera is already open
        shown = true
        guard camera == nil else { return }

        // Ask for camera permission
        let allowed = await HandCamera.allowed()

        // Stop if the screen closed or a camera opened while waiting
        guard shown, camera == nil else { return }

        // Show the no camera message if permission was refused
        guard allowed else {
            phase = .noCamera
            return
        }

        // Start the camera, or show the no front camera message if it won't start
        let cam = HandCamera()
        guard cam.start() else {
            phase = .noFrontCamera
            return
        }

        // Handle each camera frame
        cam.onFrame = { t, gap, which in

            // Note whether a hand was found in this frame
            handFound = gap != nil

            // During the test, record the sample and the left or right guess
            if phase == .running {
                samples.append(TapSample(t: t, gap: gap))
                if let which { guesses.test.append(which) }
            }

            // Keep the last 30 guesses, with "" for a frame with no guess
            guesses.recent.append(which ?? "")
            if guesses.recent.count > 30 { guesses.recent.removeFirst() }

            // Update the hand seen right now when it changes
            let seen = HandCheck.seen(guesses.recent, minFrames: HandCheck.minFramesLive)
            if seen != seenNow { seenNow = seen }
        }
        camera = cam
    }

    // Go back to setup with the given hand, clear the result and restart the camera
    private func again(_ next: String) {
        hand = next
        result = nil
        otherHand = nil
        sentences = []
        phase = .setup
        camera?.resume()
    }

    // Run the countdown and the test, then work out and show the result
    private func run() async {

        // Count down 3, 2, 1, one second each, and stop if the screen closes
        for n in [3, 2, 1] {
            phase = .countdown(n)
            announce("\(n)")
            try? await Task.sleep(for: .seconds(1))
            if !shown { return }
        }

        // Clear the samples, guesses and count, and start the test
        samples = []
        guesses.test = []
        count = 0
        phase = .running
        announce(Copy.tapGo)

        // Update the tap count every half second until the time or tap limit is reached or the screen closes
        let began = Date()
        while shown && Date().timeIntervalSince(began) < Self.maxSeconds && count < Self.maxTaps {
            try? await Task.sleep(for: .milliseconds(500))
            count = Tapping.analyzeTaps(relative()).taps
        }
        guard shown else { return }

        // Stop the camera and work out the taps for the hand tested
        camera?.stop()
        testedHand = hand
        let r = Tapping.analyzeTaps(relative())
        otherHand = nil

        // With too few frames a second, show the too slow message and keep no result
        if samples.count >= 2 && framesPerSecond() < Self.minFps {
            sentences = [Copy.tapTooSlow]
            result = nil
        } else if let other = HandCheck.otherHand(picked: hand, guesses: guesses.test) {

            // If the camera saw the other hand, show the wrong hand message and keep no result
            otherHand = other
            sentences = [Copy.tapWrongHand(other, hand)]
            result = nil
        } else {

            // Otherwise save a counted result and build the sentences, comparing with earlier counted tests on this hand
            let previous = Store.getTapTests().filter { t in t.hand == hand && t.result.counted }.reversed().map { t in t.result }
            if r.counted { Store.saveTapTest(TapTest(ts: Int(Date().timeIntervalSince1970 * 1000), hand: hand, result: r)) }
            sentences = Copy.tapSentences(r, previous: Array(previous))
            result = r
        }

        // Show the results and read out the first sentence
        phase = .done
        announce(sentences.first ?? "")
    }

    // The samples with times counted from the first frame of the test
    private func relative() -> [TapSample] {
        let t0 = samples.first?.t ?? 0
        return samples.map { s in TapSample(t: s.t - t0, gap: s.gap) }
    }

    // How many frames a second the camera and hand tracking managed during the test
    private func framesPerSecond() -> Double {
        guard let first = samples.first?.t, let last = samples.last?.t, last > first else { return 0 }
        return Double(samples.count - 1) / (last - first)
    }

    // Read the text out loud to screen readers, if it isn't empty
    private func announce(_ text: String) {
        if !text.isEmpty { UIAccessibility.post(notification: .announcement, argument: text) }
    }
}
