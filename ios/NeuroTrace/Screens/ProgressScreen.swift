// PROGRESSSCREEN.SWIFT SHOWS HOW YOUR SPIRALS CHANGED OVER TIME
// IT COMPARES YOUR FIRST AND LATEST CHECK INS, YOUR LEFT AND RIGHT HANDS, AND LISTS EVERY CHECK IN

import SwiftUI

// Get the replay line of the first spiral in a check in that has one, or nil if none do
func checkinPath(_ rec: AssessmentRecord) -> ReplayPath? {
    guard let trial = (rec.trials ?? []).first(where: { t in t.path != nil || t.samples != nil }) else { return nil }

    // Use the saved replay line, or make one from the recorded points
    return trial.path ?? replayPath(trial.samples ?? [], trial.strokeStarts ?? [0])
}

// One check in shown in a card, with its label, its result and its replay line
struct Snapshot {
    var label: String
    var rec: AssessmentRecord
    var result: Score.Result
    var path: ReplayPath?
}

// A left hand and a right hand check in, with the measures that differ most first
struct HandPair {

    // The two check ins and the rows that compare them
    var left: Snapshot
    var right: Snapshot
    var rows: [Hands.Row]

    // Make the newest pair drawn the same way, both placed against the newer one's reference group
    static func make(_ records: [AssessmentRecord], _ scoring: Scoring) -> HandPair? {
        guard let pair = Hands.latestPair(records) else { return nil }

        // Use the age group of the newer check in for both
        let bracket = (pair.left.ts >= pair.right.ts ? pair.left : pair.right).bracketChoice

        // Score a check in against the reference group
        let place = { (rec: AssessmentRecord) in
            Score.scoreSession([rec.features ?? rec.result?.features ?? [:]], scoring.model, scoring.reference, bracket)
        }
        let left = place(pair.left), right = place(pair.right)

        // Build the pair with its compare rows
        return HandPair(
            left: Snapshot(label: "Left hand", rec: pair.left, result: left, path: checkinPath(pair.left)),
            right: Snapshot(label: "Right hand", rec: pair.right, result: right, path: checkinPath(pair.right)),
            rows: Hands.compareHands(left: left.measurePct, right: right.measurePct)
        )
    }
}

// Draw a replay line up to the given time, with a dot at the pen while it is still drawing
func paintPath(_ ctx: GraphicsContext, _ size: CGSize, _ path: ReplayPath, _ upTo: Double, _ palette: Palette) {

    // Draw nothing when there is no width
    let w = Double(size.width), h = Double(size.height)
    if w == 0 { return }

    // Turn the points into Doubles
    let x = path.x.map { v in Double(v) }, y = path.y.map { v in Double(v) }, t = path.t.map { v in Double(v) }

    // Scale and center the line to fit the space with 10 points of padding
    let box = bounds((x, y))
    let pad = 10.0
    let s = min((w - 2 * pad) / or1(box.maxX - box.minX), (h - 2 * pad) / or1(box.maxY - box.minY))
    let ox = w / 2 - s * (box.minX + box.maxX) / 2, oy = h / 2 - s * (box.minY + box.maxY) / 2

    // The points where the pen lifts and a new stroke starts
    let lifts = Set(path.starts)

    // Count how many points were drawn by the given time
    var n = 0
    while n < t.count && t[n] <= upTo { n += 1 }

    // Draw those points, moving to the start of each stroke
    var line = Path()
    for i in 0..<n {
        let point = CGPoint(x: ox + s * x[i], y: oy + s * y[i])
        if i == 0 || lifts.contains(i) { line.move(to: point) } else { line.addLine(to: point) }
    }
    ctx.stroke(line, with: .color(palette.accent.color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

    // Draw a dot at the last drawn point while the line is not finished
    if n > 0 && n < t.count {
        let c = CGPoint(x: ox + s * x[n - 1], y: oy + s * y[n - 1])
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(palette.accent.color))
    }
}


// THE PROGRESS MODEL

// Holds what the progress screen needs, and handles the replay
@MainActor
@Observable
final class ProgressModel {

    // The main app model
    unowned let app: AppModel

    // True once the check ins have loaded, and true when there are not enough to compare
    var loaded = false
    var empty = false

    // The first and latest check ins, the latest check in, and the time the replay is up to
    var snapshots: [Snapshot] = []
    var latest: AssessmentRecord? = nil
    var upTo = Double.infinity

    // The left and right hand check ins to compare, or nil if there isn't a pair yet
    var hands: HandPair? = nil

    // Every check in, newest first, for the list at the bottom
    var history: [AssessmentRecord] = []

    // The replay animation frame
    @ObservationIgnored private var progressFrame = 0

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // Load the check ins and build the comparisons when the screen shows
    func onShow() {
        loaded = false
        Task {

            // Load every check in and find the newest left and right hand pair
            let records = (try? await Store.listAssessments()) ?? []
            history = records
            hands = (try? await app.scoring.value).flatMap { scoring in HandPair.make(records, scoring) }

            // Keep only the check ins with the hand and pen or finger used most
            let same = Meds.mainSetup(records).map { setup in records.filter { r in r.hand == setup.hand && r.inputType == setup.inputType } } ?? []

            // With fewer than 2 of them, mark the screen as empty and stop
            guard same.count >= 2, let latest = same.first, let first = same.last else {
                empty = true
                loaded = true
                return
            }

            // Wait for the scoring files, or stop if they can't load
            guard let scoring = try? await app.scoring.value else { return }

            // Score both against the newest check in's age group
            let bracket = records.first?.bracketChoice
            let place = { (rec: AssessmentRecord) in
                Score.scoreSession([rec.features ?? rec.result?.features ?? [:]], scoring.model, scoring.reference, bracket)
            }

            // Make the first and latest snapshots and mark the screen as loaded
            snapshots = [
                Snapshot(label: "First check-in", rec: first, result: place(first), path: checkinPath(first)),
                Snapshot(label: "Latest check-in", rec: latest, result: place(latest), path: checkinPath(latest)),
            ]
            self.latest = latest
            empty = false
            loaded = true

            // On the next frame, show the whole lines with Reduced Motion on, or replay them
            Frames.next { _ in
                if Motion.reduced() { self.upTo = .infinity } else { self.replayAll() }
            }
        }
    }

    // The replay lines of the snapshots that have points
    var lives: [ReplayPath] { snapshots.compactMap { s in s.path?.t.isEmpty == false ? s.path : nil } }

    // Replay every line at the same time, from the start
    func replayAll() {
        Frames.cancel(progressFrame)

        // Find the time the longest line ends
        let end = lives.reduce(0.0) { m, l in max(m, Double(l.t[l.t.count - 1])) }
        let start = Frames.now()
        upTo = 0

        // Each frame, show the points drawn so far, and ask for another frame until the end or until the screen changes
        func step(_ now: Double) {
            let elapsed = (now - start) / 1000
            upTo = elapsed
            if elapsed < end && app.screen == .progress { progressFrame = Frames.next(step) }
        }
        progressFrame = Frames.next(step)
    }
}


// THE SCREEN

// The progress screen itself
struct ProgressScreen: View {

    // The app model, colors and text sizes shared by every screen
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.progress

        // Use a wider page on wide screens
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, tabbed: true, titled: true) { _ in

            // The headline and a short description
            H1(text: "Progress")
            Text(Copy.progressBlurb).text(.lede).padding(.top, 10)

            // Once loaded, show the first and latest check ins, the hands and the list
            if m.loaded {

                // With fewer than 2 check ins, show the mascot and a note
                if m.empty || m.snapshots.count < 2 {
                    Card(alignment: .center) {
                        Mascot(mood: "idle").frame(width: 72, height: 72)
                        Text(Copy.progressEmpty).text(.lede).multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)
                } else {

                    // Otherwise compare the first and latest check ins
                    filled(m)
                }
                hands(m)
                history(m)
            }
        }
    }

    // Every check in, newest first, each one opening its result
    @ViewBuilder
    private func history(_ m: ProgressModel) -> some View {
        Text("Your check-ins").text(.sectionTitle).padding(.top, 28)

        // With no check ins, show a note
        if m.history.isEmpty {
            Card(alignment: .center) {
                Text(Copy.historyEmpty).text(.lede).multilineTextAlignment(.center)
            }
            .padding(.top, 12)
        } else {

            // Otherwise show one row per check in, with a thin line between rows
            Card(padding: 0, spacing: 0) {
                ForEach(0..<m.history.count, id: \.self) { i in
                    let rec = m.history[i]
                    if i > 0 { Hairline() }

                    // The date and the result level, opening the result when tapped
                    HistoryRow(when: historyWhen(rec.ts), sub: rec.result.map { r in Copy.tiers[r.tier].label } ?? "") {
                        app.go(.results, "\(rec.id ?? 0)")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)
        }
    }

    // The left hand next to the right hand
    @ViewBuilder
    private func hands(_ m: ProgressModel) -> some View {
        Text("Left vs right hand").text(.sectionTitle).padding(.top, 28)

        // With a pair, show both hands and compare them
        if let pair = m.hands {

            // What the two check ins were drawn with
            Text(Copy.handsSetup(pair.left.rec.inputType)).text(.sub).padding(.top, 8)

            // The two hands side by side
            HStack(alignment: .top, spacing: 12) {
                snapshot(pair.left, .infinity)
                snapshot(pair.right, .infinity)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)

            // The measures, biggest differences first
            ResultCard(title: "Biggest differences first") {
                Text(Copy.handsCaption).text(.sub)
                legend("Left", "Right")
                ForEach(pair.rows, id: \.key) { row in compareRow(row.key, row.left, row.right, ("Left", "Right")) }
            }
            .padding(.top, 16)
        } else {

            // Without a pair, show a note
            Card(alignment: .center) {
                Text(Copy.handsEmpty).text(.lede).multilineTextAlignment(.center)
            }
            .padding(.top, 12)
        }
    }

    // What the hollow and the filled dots stand for
    private func legend(_ hollow: String, _ filled: String) -> some View {
        HStack(spacing: 20) {

            // The hollow dot and its label
            HStack(spacing: 8) {
                Circle().strokeBorder(p.accent.color, lineWidth: 2.5).frame(width: 14, height: 14)
                Text(hollow)
            }

            // The filled dot and its label
            HStack(spacing: 8) {
                Circle().fill(p.accent.color).frame(width: 14, height: 14)
                Text(filled)
            }
        }
        .nt(.body(15, lineHeight: 1.4))
        .foregroundStyle(p.ink2.color)
        .accessibilityHidden(true)
    }

    // The first and latest check ins compared
    @ViewBuilder
    private func filled(_ m: ProgressModel) -> some View {
        let a = m.snapshots[0].result, b = m.snapshots[1].result

        // What the latest check in was drawn with
        if let latest = m.latest {
            Text(Copy.progressSetup(latest.hand, latest.inputType)).text(.sub).padding(.top, 16)
        }

        // The two check ins side by side
        HStack(alignment: .top, spacing: 12) {
            snapshot(m.snapshots[0], m.upTo)
            snapshot(m.snapshots[1], m.upTo)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 12)

        // The replay button, when there is a line to replay
        if !m.lives.isEmpty {
            Btn(title: m.lives.count > 1 ? "Replay both" : "Replay drawing", kind: .secondary, icon: .play, compact: true) { m.replayAll() }
                .padding(.top, 12)
        }

        // The Measure by measure card
        ResultCard(title: "Measure by measure") {
            Text(Copy.progressCaption).text(.sub)
            legend("First", "Latest")

            // Each group with the measures both check ins have
            ForEach(Copy.groups, id: \.id) { g in
                let keys = NTFeatures.spiralFeatureOrder.filter { k in Copy.measures[k]?.group == g.id && a.measurePct[k] != nil && b.measurePct[k] != nil }

                // The group title and one row per measure, with a thin line on top, leaving out empty groups
                if !keys.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(g.title).text(.h3)
                        ForEach(keys, id: \.self) { k in compareRow(k, a.measurePct[k] ?? 0, b.measurePct[k] ?? 0) }
                    }
                    .fullWidth()
                    .padding(.top, 16)
                    .overlay(alignment: .top) { Hairline() }
                    .padding(.top, 4)
                }
            }
        }
        .padding(.top, 16)
    }

    // A card for one check in with its label, date, level and spiral
    private func snapshot(_ s: Snapshot, _ upTo: Double) -> some View {
        Card(spacing: 4, fill: true) {

            // The label, the date and the result level
            Text(s.label).text(.sub)
            Text(whenText(s.rec.ts)).nt(.display(19, 600, lineHeight: 1.2)).foregroundStyle(p.ink.color)
            Text(Copy.tiers[s.result.tier].label).text(.body)

            // The spiral drawn up to the given time, and how long it took
            if let path = s.path, !path.t.isEmpty {
                Canvas { ctx, size in paintPath(ctx, size, path, upTo, p) }
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.top, 8)
                    .accessibilityElement()
                    .accessibilityLabel("Your spiral from \(whenText(s.rec.ts))")
                    .accessibilityAddTraits(.isImage)
                Text(Copy.drawnIn(Double(path.t[path.t.count - 1]))).text(.sub)
            } else {

                // With no spiral, show a note
                Text(Copy.replayMissing).text(.sub)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // One measure for two check ins, with the first one as the hollow dot
    private func compareRow(_ key: String, _ first: Double, _ latest: Double, _ labels: (String, String) = ("First", "Latest")) -> some View {
        VStack(alignment: .leading, spacing: 4) {

            // The measure name, a sentence for each check in, and the track with both dots
            Text(Copy.measures[key]?.name ?? key).text(.strong)
            Text("\(labels.0): \(Copy.measureSentence(key, first))").text(.sub)
            Text("\(labels.1): \(Copy.measureSentence(key, latest))").text(.sub)
            Track(dots: [(frac: first, then: true), (frac: latest, then: false)])
        }
        .fullWidth()
        .padding(.top, 10)
    }
}
