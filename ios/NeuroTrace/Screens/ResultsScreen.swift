import SwiftUI

// never show result.score itself - a 0 to 1 model output reads as "chance you have Parkinson's", which it is not.
// What the model card shows instead: result.scorePct (where the combined result sits among the healthy
// reference group) and result.contributions (how far each measure moved it, in the model's own units).
let whenFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("MMMdjmm")
    return format
}()

func whenText(_ ts: Int) -> String { whenFmt.string(from: Date(timeIntervalSince1970: Double(ts) / 1000)) }

struct Box {
    var minX = Double.infinity
    var maxX = -Double.infinity
    var minY = Double.infinity
    var maxY = -Double.infinity
}

func bounds(_ lines: ([Double], [Double])...) -> Box {
    var box = Box()
    for (x, y) in lines {
        for i in 0..<x.count {
            if x[i] < box.minX { box.minX = x[i] }
            if x[i] > box.maxX { box.maxX = x[i] }
            if y[i] < box.minY { box.minY = y[i] }
            if y[i] > box.maxY { box.maxY = y[i] }
        }
    }
    return box
}

func or1(_ v: Double) -> Double { v != 0 && !v.isNaN ? v : 1 }

struct Prepared {
    var t: [Double]
    var raw: ([Double], [Double])
    var filtered: ([Double], [Double])
    var starts: Set<Int>
    var speeds: [Double]
    var box: Box
}

func prepareDrawing(_ trial: AssessmentTrial) throws -> Prepared {
    let samples = trial.samples ?? []
    let t = samples.map { s in s.t }
    let x = samples.map { s in s.x }
    let y = samples.map { s in s.y }
    let raw = NTFeatures.normalize(x, y)
    let (_, fx, fy) = try NTFeatures.preprocessTrace(t, x, y)
    let filtered = (fx, fy)
    let starts = Set(trial.strokeStarts ?? [0])
    var speeds: [Double] = []
    for i in stride(from: 1, to: samples.count, by: 1) {
        let dt = samples[i].t - samples[i - 1].t
        if starts.contains(i) || dt <= 0 { continue }
        speeds.append(hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y) / dt)
    }
    return Prepared(t: t, raw: raw, filtered: filtered, starts: starts, speeds: speeds, box: bounds(raw, filtered))
}

func strokeLine(_ ctx: GraphicsContext, _ line: ([Double], [Double]), _ map: (Double, Double) -> CGPoint, _ n: Int, _ starts: Set<Int>?, _ style: Color, _ width: CGFloat) {
    var path = Path()
    for i in 0..<n {
        let point = map(line.0[i], line.1[i])
        if i == 0 || starts?.contains(i) == true { path.move(to: point) } else { path.addLine(to: point) }
    }
    ctx.stroke(path, with: .color(style), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

func paintDrawing(_ ctx: GraphicsContext, _ size: CGSize, _ d: Prepared, _ upTo: Double, _ palette: Palette) {
    let w = Double(size.width), h = Double(size.height)
    let pad = 16.0
    let s = min((w - 2 * pad) / or1(d.box.maxX - d.box.minX), (h - 2 * pad) / or1(d.box.maxY - d.box.minY))
    let ox = w / 2 - s * (d.box.minX + d.box.maxX) / 2, oy = h / 2 - s * (d.box.minY + d.box.maxY) / 2
    let map = { (x: Double, y: Double) in CGPoint(x: ox + s * x, y: oy + s * y) }
    var n = d.raw.0.count
    if upTo < Double.infinity {
        n = 0
        while n < d.t.count && d.t[n] <= upTo { n += 1 }
    }
    var faded = ctx
    faded.opacity = 0.55
    strokeLine(faded, d.raw, map, n, d.starts, palette.ink2.color, 1.5)
    if n == d.raw.0.count { strokeLine(ctx, d.filtered, map, d.filtered.0.count, nil, palette.accent.color, 3) }
}

func paintSpeed(_ ctx: GraphicsContext, _ size: CGSize, _ speeds: [Double], _ palette: Palette) {
    let w = Double(size.width), h = Double(size.height)
    if speeds.count < 2 { return }
    var top = 1.0
    for v in speeds { if v > top { top = v } } // spread overflows
    let X = { (i: Int) in (Double(i) / Double(speeds.count - 1)) * w }, Y = { (v: Double) in h - 4 - (v / top) * (h - 8) }
    var area = Path()
    area.move(to: CGPoint(x: 0, y: h))
    for (i, v) in speeds.enumerated() { area.addLine(to: CGPoint(x: X(i), y: Y(v))) }
    area.addLine(to: CGPoint(x: w, y: h))
    area.closeSubpath()
    ctx.fill(area, with: .color(palette.accentSoft.color))
    var line = Path()
    for (i, v) in speeds.enumerated() {
        if i == 0 { line.move(to: CGPoint(x: X(i), y: Y(v))) } else { line.addLine(to: CGPoint(x: X(i), y: Y(v))) }
    }
    ctx.stroke(line, with: .color(palette.accent.color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
}

@MainActor
@Observable
final class ResultsModel {
    unowned let app: AppModel
    var rec: AssessmentRecord? = nil
    var renderID = 0
    var which = 0
    var drawnCount = 0
    var prepared: Prepared? = nil
    var upTo = Double.infinity
    @ObservationIgnored private var frame = 0

    init(app: AppModel) { self.app = app }

    func onShow(_ id: String?) {
        rec = nil
        if let id {
            Task {
                let found = try? await Store.getAssessment(Int(id) ?? -1)
                guard let found, found.result != nil else { return app.go(.dashboard) }
                app.current = found
                renderResults(found)
            }
            return
        }
        if let current = app.current { renderResults(current) }
    }

    private func renderResults(_ rec: AssessmentRecord) {
        self.rec = rec
        renderID += 1
        drawingCard(rec)
    }

    private func drawn() -> [AssessmentTrial] { (rec?.trials ?? []).filter { t in t.samples != nil } }

    private func drawingCard(_ rec: AssessmentRecord) {
        Frames.cancel(frame)
        upTo = .infinity
        which = 0
        prepared = nil
        let trials = drawn()
        drawnCount = trials.count
        guard let trial = trials.first else { return }
        do {
            prepared = try prepareDrawing(trial)
        } catch {
            print("NeuroTrace: couldn't prepare the drawing", error)
        }
    }

    func pick(_ i: Int) {
        let trials = drawn()
        if i >= trials.count { return }
        do {
            prepared = try prepareDrawing(trials[i])
        } catch {
            return print("NeuroTrace: couldn't prepare that spiral", error)
        }
        which = i
        Frames.cancel(frame)
        upTo = .infinity
    }

    func replayDrawing() {
        guard let prepared, let end = prepared.t.last else { return }
        Frames.cancel(frame)
        let start = Frames.now()
        func step(_ now: Double) {
            let elapsed = (now - start) / 1000
            upTo = elapsed >= end ? .infinity : elapsed
            if elapsed < end { frame = Frames.next(step) }
        }
        frame = Frames.next(step)
    }
}

struct ResultCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card {
            Text(title).text(.cardTitle)
            content()
        }
    }
}

private func measureParts(_ key: String, _ frac: Double) -> (lead: String, n: Int, tail: String) {
    let sentence = Copy.measureSentence(key, frac)
    guard let hit = sentence.range(of: #"\d+%"#, options: .regularExpression) else { return (sentence, 0, "") }
    let digits = sentence[hit].dropLast()
    return (String(sentence[..<hit.lowerBound]), Int(digits) ?? 0, "%" + String(sentence[hit.upperBound...]))
}

struct MeasureRow: View {
    let key: String
    let frac: Double
    let index: Int
    var grouped = false
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo
    @State private var shown: Int? = nil
    @State private var revealed = false

    var body: some View {
        let parts = measureParts(key, frac)
        let font = NTFont.body(15, lineHeight: 1.4)
        VStack(alignment: .leading, spacing: 4) {
            Text(Copy.measures[key]?.name ?? key).text(.strong)
            (ntText(parts.lead, font, typo) + ntText("\(shown ?? parts.n)", font, typo).monospacedDigit() + ntText(parts.tail, font, typo))
                .lineSpacing(lineGap(font, typo))
                .foregroundStyle(p.ink2.color)
                .fixedSize(horizontal: false, vertical: true)
            Track(dots: [(frac: frac, then: false)], active: revealed)
        }
        .fullWidth()
        .padding(.top, grouped ? 10 : 14)
        .overlay(alignment: .top) { if !grouped { Hairline() } }
        .reveal(index) {
            revealed = true
            Motion.countUp(parts.n) { v in shown = v }
        }
    }
}

// The percentile of the combined model result among the healthy reference group, counted up on reveal
private struct ModelScore: View {
    let scorePct: Double
    let referenceN: Int
    let index: Int
    @Environment(\.palette) private var p
    @State private var shown: Int? = nil

    var body: some View {
        let pct = Int(jsRound(scorePct * 100))
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(shown ?? pct)%")
                .nt(.body(40, 600, lineHeight: 1.1))
                .monospacedDigit()
                .foregroundStyle(p.accent.color)
            Text(Copy.modelScoreSentence(referenceN: referenceN))
                .text(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fullWidth()
        .padding(.top, 12)
        // Number on top, sentence underneath. Side by side, the sentence wrapped into a narrow
        // column and hung below the number, so the two never lined up
        .accessibilityElement()
        .accessibilityLabel("\(pct)% \(Copy.modelScoreSentence(referenceN: referenceN))")
        .reveal(index) { Motion.countUp(pct, from: 0) { v in shown = v } }
    }
}

// One measure's share of the model's result. The length comes from Score.contributionBars, which is tested
private struct ContribRow: View {
    let bar: Score.Bar
    let index: Int
    @Environment(\.palette) private var p
    @State private var grown = false

    var body: some View {
        let name = Copy.measures[bar.key]?.name ?? bar.key
        let effect = bar.raises ? Copy.contribRaised : Copy.contribLowered
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).text(.strong)
                Spacer(minLength: 0)
                Text(effect).text(.sub)
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(p.fill.color).frame(width: w, height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(bar.raises ? p.accent.color : p.ink2.color)
                        .frame(width: grown ? max(w * min(bar.frac, 1), 3) : 0, height: 6)
                        .animation(.easeOut(duration: 0.55), value: grown)
                }
            }
            .frame(height: 6)
        }
        .fullWidth()
        .padding(.top, 12)
        .accessibilityElement()
        .accessibilityLabel("\(name), \(effect)")
        .reveal(index) { grown = true }
    }
}

private struct Levels: View {
    let tier: Int
    @Environment(\.palette) private var p
    @State private var filled = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                let on = i == tier
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(on ? p.accent.color : p.fill.color)
                        .frame(height: 8)
                        .scaleEffect(x: on && !filled ? 0 : 1, y: 1, anchor: .leading)
                    Text(Copy.tierShort[i])
                        .nt(.body(15, on ? 600 : 400, lineHeight: 1.3))
                        .foregroundStyle(on ? p.ink.color : p.ink2.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 18)
        .accessibilityElement()
        .accessibilityLabel("Result level: \(Copy.tierShort[tier]), \(tier + 1) of 3")
        .onAppear {
            if Motion.reduced() {
                filled = true
                return
            }
            withAnimation(Theme.ease(760).delay(0.26)) { filled = true }
        }
    }
}

private struct DrawingCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let m = app.results
        if let prepared = m.prepared {
            ResultCard(title: "Your drawing") {
                if m.drawnCount > 1 {
                    Segmented(
                        options: (0..<m.drawnCount).map { i in (value: "\(i)", label: "Spiral \(i + 1)") },
                        selected: "\(m.which)"
                    ) { value, _ in m.pick(Int(value) ?? 0) }
                    .accessibilityLabel("Which spiral to show")
                }
                Canvas { ctx, size in paintDrawing(ctx, size, prepared, m.upTo, p) }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 320)
                    .fullWidth(.center)
                    .accessibilityElement()
                    .accessibilityLabel("Your recorded line drawn under the smoothed version the measures are taken from")
                    .accessibilityAddTraits(.isImage)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(p.ink2.color).frame(width: 22, height: 2).offset(y: -4)
                        Text(Copy.rawLegend).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(p.accent.color).frame(width: 22, height: 4).offset(y: -3)
                        Text(Copy.filteredLegend).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .nt(.body(15, lineHeight: 1.4))
                .foregroundStyle(p.ink2.color)
                Btn(title: "Replay drawing", kind: .secondary, icon: .play, compact: true) { m.replayDrawing() }
                Hairline().padding(.vertical, 6)
                Text("Speed along the line").text(.h3)
                Text(Copy.speedCaption).text(.sub)
                Canvas { ctx, size in paintSpeed(ctx, size, prepared.speeds, p) }
                    .frame(height: 88)
                    .accessibilityElement()
                    .accessibilityLabel("Drawing speed over time")
                    .accessibilityAddTraits(.isImage)
            }
        } else {
            ResultCard(title: "Your drawing") {
                Text(Copy.replayMissing).text(.sub)
            }
        }
    }
}

private struct ResultsBody: View {
    let rec: AssessmentRecord
    let result: Score.Result
    @Environment(\.typo) private var typo
    @Environment(\.palette) private var p

    private func shown(_ k: String) -> Bool { result.measurePct[k] != nil }

    private var stoodOutKeys: [String] { Score.pushedUp(result).filter { k in shown(k) } }

    private var groups: [(group: Copy.Group, keys: [String])] {
        Copy.groups.compactMap { g in
            let keys = NTFeatures.spiralFeatureOrder.filter { k in Copy.measures[k]?.group == g.id && shown(k) }
            return keys.isEmpty ? nil : (group: g, keys: keys)
        }
    }

    var body: some View {
        let tier = Copy.tiers[result.tier]
        if typo.width >= 900 {
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 0) {
                    summary.reveal(0)
                    Levels(tier: result.tier).reveal(1)
                    reference.reveal(2)
                    meaning(tier).padding(.top, 28).reveal(3)
                    todo(tier).padding(.top, 16).reveal(6)
                    DrawingCard().padding(.top, 16).reveal(7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 0) {
                    stoodOut.reveal(4)
                    modelCard(5).padding(.top, 16)
                    every.padding(.top, 16).reveal(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                summary.reveal(0)
                Levels(tier: result.tier).reveal(1)
                reference.reveal(2)
                meaning(tier).padding(.top, 28).reveal(3)
                stoodOut.padding(.top, 16).reveal(4)
                modelCard(5).padding(.top, 16)
                todo(tier).padding(.top, 16).reveal(6)
                DrawingCard().padding(.top, 16).reveal(7)
                every.padding(.top, 16).reveal(8)
            }
        }
    }

    private var summary: some View {
        Text(Copy.resultSummary)
            .nt(.body(19, 600, lineHeight: 1.45))
            .foregroundStyle(p.ink.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    private var reference: some View {
        Text(Copy.referenceSentence(referenceN: result.referenceN, bracketKey: result.bracketKey, deviceMatched: result.deviceMatched))
            .text(.sub)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 18)
    }

    private func meaning(_ tier: Copy.Tier) -> some View {
        ResultCard(title: "What this means") {
            ForEach(0..<tier.meaning.count, id: \.self) { i in
                Text(tier.meaning[i]).text(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func todo(_ tier: Copy.Tier) -> some View {
        ResultCard(title: "What you can do") {
            Text(tier.todo).text(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stoodOut: some View {
        ResultCard(title: "What stood out") {
            if stoodOutKeys.isEmpty {
                Text(Copy.nothingPushedUp).text(.body).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(Copy.stoodOutCaption).text(.sub)
                ForEach(0..<stoodOutKeys.count, id: \.self) { i in
                    MeasureRow(key: stoodOutKeys[i], frac: result.measurePct[stoodOutKeys[i]] ?? 0, index: i)
                }
            }
        }
    }

    private func modelCard(_ base: Int) -> some View {
        let bars = Score.contributionBars(result)
        return ResultCard(title: "How the model read it") {
            Text(Copy.modelCardCaption).text(.sub).fixedSize(horizontal: false, vertical: true)
            ModelScore(scorePct: result.scorePct, referenceN: result.referenceN, index: base)
            Text(Copy.modelDisclaimer).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            if !bars.isEmpty {
                Text(Copy.contribCaption).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                ForEach(0..<bars.count, id: \.self) { i in
                    ContribRow(bar: bars[i], index: base + i)
                }
            }
            Hairline().padding(.vertical, 8)
            Text(Copy.modelNote + (result.deviceMatched ? "" : " " + Copy.referenceInTraining)).text(.sub).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var every: some View {
        let first = stoodOutKeys.count
        let groups = self.groups
        let offsets = groups.indices.map { g in groups[..<g].reduce(0) { n, entry in n + entry.keys.count } }
        return ResultCard(title: "Every measure") {
            Text(Copy.everyMeasureCaption).text(.sub)
            HStack {
                Text("Lowest")
                Spacer(minLength: 0)
                Text("Halfway")
                Spacer(minLength: 0)
                Text("Highest")
            }
            .nt(.body(15, lineHeight: 1.4))
            .foregroundStyle(p.ink2.color)
            .padding(.horizontal, 8)
            .accessibilityHidden(true)
            ForEach(0..<groups.count, id: \.self) { g in
                VStack(alignment: .leading, spacing: 4) {
                    Text(groups[g].group.title).text(.h3)
                    Text(groups[g].group.desc).text(.sub)
                    ForEach(0..<groups[g].keys.count, id: \.self) { i in
                        let k = groups[g].keys[i]
                        MeasureRow(key: k, frac: result.measurePct[k] ?? 0, index: first + offsets[g] + i, grouped: true)
                    }
                }
                .fullWidth()
                .padding(.top, 16)
                .overlay(alignment: .top) { Hairline() }
                .padding(.top, 4)
            }
        }
    }
}

struct ResultsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.results
        ScreenView(maxWidth: typo.width >= 900 ? 1040 : 560, titled: true) { _ in
            HStack(spacing: 12) {
                Text(m.rec.map { r in "Spiral check-in · \(whenText(r.ts))" } ?? "").text(.sub)
                Spacer(minLength: 0)
                BarLink(label: "Done", strong: true) { app.go(.dashboard) }
            }
            .frame(minHeight: 44)

            H1(text: m.rec?.result.map { r in Copy.tiers[r.tier].label } ?? "", size: 32, lineHeight: 1.12, top: 14)

            if let rec = m.rec, let result = rec.result {
                ResultsBody(rec: rec, result: result).id(m.renderID)
            }

            HStack(spacing: 12) {
                Btn(title: "Check again", kind: .secondary) { app.go(.about) }
                Btn(title: "Done") { app.go(.dashboard) }
            }
            .padding(.top, 52)
        }
    }
}
