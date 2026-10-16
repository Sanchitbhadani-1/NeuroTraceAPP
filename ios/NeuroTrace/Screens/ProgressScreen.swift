import SwiftUI

func checkinPath(_ rec: AssessmentRecord) -> ReplayPath? {
    guard let trial = (rec.trials ?? []).first(where: { t in t.path != nil || t.samples != nil }) else { return nil }
    return trial.path ?? replayPath(trial.samples ?? [], trial.strokeStarts ?? [0])
}

struct Snapshot {
    var label: String
    var rec: AssessmentRecord
    var result: Score.Result
    var path: ReplayPath?
}

func paintPath(_ ctx: GraphicsContext, _ size: CGSize, _ path: ReplayPath, _ upTo: Double, _ palette: Palette) {
    let w = Double(size.width), h = Double(size.height)
    if w == 0 { return }
    let x = path.x.map { v in Double(v) }, y = path.y.map { v in Double(v) }, t = path.t.map { v in Double(v) }
    let box = bounds((x, y))
    let pad = 10.0
    let s = min((w - 2 * pad) / or1(box.maxX - box.minX), (h - 2 * pad) / or1(box.maxY - box.minY))
    let ox = w / 2 - s * (box.minX + box.maxX) / 2, oy = h / 2 - s * (box.minY + box.maxY) / 2
    let lifts = Set(path.starts)
    var n = 0
    while n < t.count && t[n] <= upTo { n += 1 }
    var line = Path()
    for i in 0..<n {
        let point = CGPoint(x: ox + s * x[i], y: oy + s * y[i])
        if i == 0 || lifts.contains(i) { line.move(to: point) } else { line.addLine(to: point) }
    }
    ctx.stroke(line, with: .color(palette.accent.color), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    if n > 0 && n < t.count {
        let c = CGPoint(x: ox + s * x[n - 1], y: oy + s * y[n - 1])
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(palette.accent.color))
    }
}

@MainActor
@Observable
final class ProgressModel {
    unowned let app: AppModel
    var loaded = false
    var empty = false
    var snapshots: [Snapshot] = []
    var latest: AssessmentRecord? = nil
    var upTo = Double.infinity
    // Every check-in, newest first, for the list at the bottom
    var history: [AssessmentRecord] = []
    @ObservationIgnored private var progressFrame = 0

    init(app: AppModel) { self.app = app }

    func onShow() {
        loaded = false
        Task {
            let records = (try? await Store.listAssessments()) ?? []
            history = records
            let same = records
            guard same.count >= 2, let latest = same.first, let first = same.last else {
                empty = true
                loaded = true
                return
            }
            guard let scoring = try? await app.scoring.value else { return }
            // Both placed against the newest check-in's reference group, the same as the medication chart
            let bracket = records.first?.bracketChoice
            let place = { (rec: AssessmentRecord) in
                Score.scoreSession([rec.features ?? rec.result?.features ?? [:]], scoring.model, scoring.reference, bracket)
            }
            snapshots = [
                Snapshot(label: "First check-in", rec: first, result: place(first), path: checkinPath(first)),
                Snapshot(label: "Latest check-in", rec: latest, result: place(latest), path: checkinPath(latest)),
            ]
            self.latest = latest
            empty = false
            loaded = true
            Frames.next { _ in
                if Motion.reduced() { self.upTo = .infinity } else { self.replayAll() }
            }
        }
    }

    var lives: [ReplayPath] { snapshots.compactMap { s in s.path?.t.isEmpty == false ? s.path : nil } }

    func replayAll() {
        Frames.cancel(progressFrame)
        let end = lives.reduce(0.0) { m, l in max(m, Double(l.t[l.t.count - 1])) }
        let start = Frames.now()
        upTo = 0
        func step(_ now: Double) {
            let elapsed = (now - start) / 1000
            upTo = elapsed
            if elapsed < end && app.screen == .progress { progressFrame = Frames.next(step) }
        }
        progressFrame = Frames.next(step)
    }
}

struct ProgressScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.progress
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, tabbed: true, titled: true) { _ in
            H1(text: "Progress")
            Text(Copy.progressBlurb).text(.lede).padding(.top, 10)
            // first vs latest check-in
            if m.loaded {
                if m.empty || m.snapshots.count < 2 {
                    Card(alignment: .center) {
                        Mascot(mood: "idle").frame(width: 72, height: 72)
                        Text(Copy.progressEmpty).text(.lede).multilineTextAlignment(.center)
                    }
                    .padding(.top, 12)
                } else {
                    filled(m)
                }
                history(m)
            }
        }
    }

    // Every check-in, newest first. Each one opens its result
    @ViewBuilder
    private func history(_ m: ProgressModel) -> some View {
        Text("Your check-ins").text(.sectionTitle).padding(.top, 28)
        if m.history.isEmpty {
            Card(alignment: .center) {
                Text(Copy.historyEmpty).text(.lede).multilineTextAlignment(.center)
            }
            .padding(.top, 12)
        } else {
            Card(padding: 0, spacing: 0) {
                ForEach(0..<m.history.count, id: \.self) { i in
                    let rec = m.history[i]
                    if i > 0 { Hairline() }
                    HistoryRow(when: historyWhen(rec.ts), sub: rec.result.map { r in Copy.tiers[r.tier].label } ?? "") {
                        app.go(.results, "\(rec.id ?? 0)")
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.top, 12)
        }
    }

    // What the hollow and the filled dots stand for
    private func legend(_ hollow: String, _ filled: String) -> some View {
        HStack(spacing: 20) {
            HStack(spacing: 8) {
                Circle().strokeBorder(p.accent.color, lineWidth: 2.5).frame(width: 14, height: 14)
                Text(hollow)
            }
            HStack(spacing: 8) {
                Circle().fill(p.accent.color).frame(width: 14, height: 14)
                Text(filled)
            }
        }
        .nt(.body(15, lineHeight: 1.4))
        .foregroundStyle(p.ink2.color)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func filled(_ m: ProgressModel) -> some View {
        let a = m.snapshots[0].result, b = m.snapshots[1].result
        if let latest = m.latest {
            Text(Copy.progressSetup(latest.hand, latest.inputType)).text(.sub).padding(.top, 16)
        }
        HStack(alignment: .top, spacing: 12) {
            snapshot(m.snapshots[0], m.upTo)
            snapshot(m.snapshots[1], m.upTo)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 12)
        if !m.lives.isEmpty {
            Btn(title: m.lives.count > 1 ? "Replay both" : "Replay drawing", kind: .secondary, icon: .play, compact: true) { m.replayAll() }
                .padding(.top, 12)
        }
        ResultCard(title: "Measure by measure") {
            Text(Copy.progressCaption).text(.sub)
            legend("First", "Latest")
            ForEach(Copy.groups, id: \.id) { g in
                let keys = NTFeatures.spiralFeatureOrder.filter { k in Copy.measures[k]?.group == g.id && a.measurePct[k] != nil && b.measurePct[k] != nil }
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

    private func snapshot(_ s: Snapshot, _ upTo: Double) -> some View {
        Card(spacing: 4, fill: true) {
            Text(s.label).text(.sub)
            Text(whenText(s.rec.ts)).nt(.display(19, 600, lineHeight: 1.2)).foregroundStyle(p.ink.color)
            Text(Copy.tiers[s.result.tier].label).text(.body)
            if let path = s.path, !path.t.isEmpty {
                Canvas { ctx, size in paintPath(ctx, size, path, upTo, p) }
                    .aspectRatio(1, contentMode: .fit)
                    .padding(.top, 8)
                    .accessibilityElement()
                    .accessibilityLabel("Your spiral from \(whenText(s.rec.ts))")
                    .accessibilityAddTraits(.isImage)
                Text(Copy.drawnIn(Double(path.t[path.t.count - 1]))).text(.sub)
            } else {
                Text(Copy.replayMissing).text(.sub)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // One measure for two check-ins. The first one is the hollow dot
    private func compareRow(_ key: String, _ first: Double, _ latest: Double, _ labels: (String, String) = ("First", "Latest")) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Copy.measures[key]?.name ?? key).text(.strong)
            Text("\(labels.0): \(Copy.measureSentence(key, first))").text(.sub)
            Text("\(labels.1): \(Copy.measureSentence(key, latest))").text(.sub)
            Track(dots: [(frac: first, then: true), (frac: latest, then: false)])
        }
        .fullWidth()
        .padding(.top, 10)
    }
}
