import Charts
import SwiftUI
import UIKit

// Vision's left or right guesses, newest last. A class, so a new frame doesn't redraw the screen
private final class HandGuesses {
    // The last second or so, for the hint while getting ready. "" is a frame with no guess
    var recent: [String] = []
    // Every guess during the test itself
    var test: [String] = []
}

// The warning for iPads too old for Apple's hand tracking, on the Testing card and before a test
struct OldIPadNote: View {
    @Environment(\.palette) private var p

    var body: some View {
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

// Shown full screen from the Testing tab's card, so it needs no route
struct TapTestScreen: View {
    let close: () -> Void
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo
    @State private var camera: HandCamera?
    @State private var hand = Store.getPrefs().hand
    @State private var phase = Phase.setup
    @State private var handFound = false
    @State private var samples: [TapSample] = []
    @State private var count = 0
    @State private var result: TapResult?
    // The hand the result is for
    @State private var testedHand = "right"
    @State private var sentences: [String] = []
    @State private var shown = false
    @State private var guesses = HandGuesses()
    // The hand the camera sees right now, when it can tell
    @State private var seenNow: String?
    // Set when the test clearly used the other hand, so it wasn't saved
    @State private var otherHand: String?

    // noCamera is a refused permission, noFrontCamera is a device without one (like the Simulator)
    enum Phase: Equatable { case setup, countdown(Int), running, done, noCamera, noFrontCamera }

    static let maxTaps = 10
    static let maxSeconds = 15.0
    // With fewer camera frames a second than this, fast taps blur together, so the test isn't kept
    static let minFps = 12.0

    var body: some View {
        ScreenView { _ in
            BackLink(label: "Testing") { close() }
            H1(text: "Finger tapping")
            switch phase {
            case .noCamera:
                Text(Copy.tapNoCamera).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                Btn(title: "Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .padding(.top, 24)
            case .noFrontCamera:
                Text(Copy.tapNoFrontCamera).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                Btn(title: "Back to Testing", kind: .secondary) { close() }.padding(.top, 24)
            case .done:
                results
            default:
                live
            }
        }
        .background(p.bg.color.ignoresSafeArea())
        .onAppear { Task { await open() } }
        .onDisappear {
            shown = false
            // Let go of the camera, so it stops and its frame handler doesn't keep it alive
            camera?.onFrame = { _, _, _ in }
            camera?.stop()
            camera = nil
        }
    }

    private var live: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(phase == .running ? Copy.tapGo : Copy.tapTips).text(.lede).fixedSize(horizontal: false, vertical: true)
            if phase == .setup && !HandTracking.newEnoughHere { OldIPadNote() }
            // The hand can only change before the test starts
            Segmented(options: [("left", "Left hand"), ("right", "Right hand")], selected: hand) { value, _ in
                if phase == .setup { hand = value }
            }
            .opacity(phase == .setup ? 1 : 0.45)
            .allowsHitTesting(phase == .setup)
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
            // Smaller on short screens, so Start stays in view
            .frame(height: min(380, max(220, typo.height * 0.42)))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Camera view. \(status)")
            Text(Copy.tapOnDevice).text(.sub).fixedSize(horizontal: false, vertical: true)
            if phase == .setup {
                Btn(title: "Start", disabled: camera == nil) { Task { await run() } }
            }
        }
        .padding(.top, 12)
    }

    private var status: String {
        switch phase {
        case let .countdown(n): return "\(n)"
        case .running: return "\(count) \(count == 1 ? "tap" : "taps")"
        default:
            if let seen = seenNow, seen != hand { return Copy.tapLooksLike(seen) }
            return handFound ? "Hand found" : "Show your \(hand) hand to the camera"
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(testedHand == "left" ? "Left hand" : "Right hand").text(.sub)
            ForEach(sentences, id: \.self) { Text($0).text(.body).fixedSize(horizontal: false, vertical: true) }
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
            Text(Copy.tapNotDiagnosis).text(.sub).fixedSize(horizontal: false, vertical: true)
            if let other = otherHand {
                Btn(title: "Switch to \(other) hand and try again") { again(other) }
                    .padding(.top, 12)
                Btn(title: "Try again with \(testedHand) hand", kind: .secondary) { again(testedHand) }
            } else if result?.counted == true {
                Btn(title: "Now the other hand") { again(testedHand == "left" ? "right" : "left") }
                    .padding(.top, 12)
            } else {
                Btn(title: "Try again") { again(testedHand) }
                    .padding(.top, 12)
            }
            Btn(title: "Done", kind: .secondary) { close() }
        }
        .padding(.top, 16)
    }

    private func open() async {
        shown = true
        guard camera == nil else { return }
        let allowed = await HandCamera.allowed()
        // The screen may have closed, or opened a camera already, while the permission question was up
        guard shown, camera == nil else { return }
        guard allowed else {
            phase = .noCamera
            return
        }
        let cam = HandCamera()
        guard cam.start() else {
            phase = .noFrontCamera
            return
        }
        cam.onFrame = { t, gap, which in
            handFound = gap != nil
            if phase == .running {
                samples.append(TapSample(t: t, gap: gap))
                if let which { guesses.test.append(which) }
            }
            guesses.recent.append(which ?? "")
            if guesses.recent.count > 30 { guesses.recent.removeFirst() }
            let seen = HandCheck.seen(guesses.recent, minFrames: HandCheck.minFramesLive)
            if seen != seenNow { seenNow = seen }
        }
        camera = cam
    }

    // Back to the start for another go, with the camera running again
    private func again(_ next: String) {
        hand = next
        result = nil
        otherHand = nil
        sentences = []
        phase = .setup
        camera?.resume()
    }

    private func run() async {
        for n in [3, 2, 1] {
            phase = .countdown(n)
            announce("\(n)")
            try? await Task.sleep(for: .seconds(1))
            if !shown { return }
        }
        samples = []
        guesses.test = []
        count = 0
        phase = .running
        announce(Copy.tapGo)
        let began = Date()
        while shown && Date().timeIntervalSince(began) < Self.maxSeconds && count < Self.maxTaps {
            try? await Task.sleep(for: .milliseconds(500))
            count = Tapping.analyzeTaps(relative()).taps
        }
        guard shown else { return }
        // The preview isn't on screen with the results, so the camera rests until the next try
        camera?.stop()
        testedHand = hand
        let r = Tapping.analyzeTaps(relative())
        otherHand = nil
        if samples.count >= 2 && framesPerSecond() < Self.minFps {
            sentences = [Copy.tapTooSlow]
            result = nil
        } else if let other = HandCheck.otherHand(picked: hand, guesses: guesses.test) {
            // The camera clearly saw the other hand, so saving it under this hand would mix up the two
            otherHand = other
            sentences = [Copy.tapWrongHand(other, hand)]
            result = nil
        } else {
            let previous = Store.getTapTests().filter { t in t.hand == hand && t.result.counted }.reversed().map { t in t.result }
            if r.counted { Store.saveTapTest(TapTest(ts: Int(Date().timeIntervalSince1970 * 1000), hand: hand, result: r)) }
            sentences = Copy.tapSentences(r, previous: Array(previous))
            result = r
        }
        phase = .done
        announce(sentences.first ?? "")
    }

    // Times from the first frame of the test, as tapping.js expects
    private func relative() -> [TapSample] {
        let t0 = samples.first?.t ?? 0
        return samples.map { s in TapSample(t: s.t - t0, gap: s.gap) }
    }

    // How many frames a second the camera and hand tracking managed during the test
    private func framesPerSecond() -> Double {
        guard let first = samples.first?.t, let last = samples.last?.t, last > first else { return 0 }
        return Double(samples.count - 1) / (last - first)
    }

    private func announce(_ text: String) {
        if !text.isEmpty { UIAccessibility.post(notification: .announcement, argument: text) }
    }
}
