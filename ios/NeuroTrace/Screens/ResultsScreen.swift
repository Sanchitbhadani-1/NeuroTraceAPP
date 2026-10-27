// RESULTSSCREEN.SWIFT SHOWS THE RESULT OF A SPIRAL CHECK IN
// IT SHOWS THE RESULT LEVEL, WHAT STOOD OUT, HOW THE MODEL READ IT, THE DRAWING, AND EVERY MEASURE

import SwiftUI

// Turns a time into a short date and time, like "Oct 3, 4:05 PM"
let whenFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("MMMdjmm")
    return format
}()

// Turns a time in milliseconds into short date and time text
func whenText(_ ts: Int) -> String { whenFmt.string(from: Date(timeIntervalSince1970: Double(ts) / 1000)) }

// The smallest and largest x and y values of a drawing
struct Box {
    var minX = Double.infinity
    var maxX = -Double.infinity
    var minY = Double.infinity
    var maxY = -Double.infinity
}

// Find the box that holds every point of all the given lines
func bounds(_ lines: ([Double], [Double])...) -> Box {
    var box = Box()

    // Go through every point and grow the box to fit it
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

// Give back the number, or 1 if it is 0 or not a number
func or1(_ v: Double) -> Double { v != 0 && !v.isNaN ? v : 1 }

// A spiral that is ready to draw on screen
struct Prepared {

    // The time of each point
    var t: [Double]

    // The recorded line and the smoothed line
    var raw: ([Double], [Double])
    var filtered: ([Double], [Double])

    // Which points start a new stroke
    var starts: Set<Int>

    // The drawing speed between each pair of points
    var speeds: [Double]

    // The box that holds both lines
    var box: Box
}

// Turn one recorded spiral into a Prepared drawing
func prepareDrawing(_ trial: AssessmentTrial) throws -> Prepared {

    // Split the points into times, x values and y values
    let samples = trial.samples ?? []
    let t = samples.map { s in s.t }
    let x = samples.map { s in s.x }
    let y = samples.map { s in s.y }

    // Make the recorded line and the smoothed line
    let raw = NTFeatures.normalize(x, y)
    let (_, fx, fy) = try NTFeatures.preprocessTrace(t, x, y)
    let filtered = (fx, fy)

    // Find where each stroke starts, or start one stroke at the first point
    let starts = Set(trial.strokeStarts ?? [0])

    // Work out the speed between each pair of points, skipping new strokes and points with no time between them
    var speeds: [Double] = []
    for i in stride(from: 1, to: samples.count, by: 1) {
        let dt = samples[i].t - samples[i - 1].t
        if starts.contains(i) || dt <= 0 { continue }
        speeds.append(hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y) / dt)
    }
    return Prepared(t: t, raw: raw, filtered: filtered, starts: starts, speeds: speeds, box: bounds(raw, filtered))
}

// Draw the first n points of a line, lifting the pen at each stroke start
func strokeLine(_ ctx: GraphicsContext, _ line: ([Double], [Double]), _ map: (Double, Double) -> CGPoint, _ n: Int, _ starts: Set<Int>?, _ style: Color, _ width: CGFloat) {
    var path = Path()

    // Move to the first point of each stroke and draw a line to every other point
    for i in 0..<n {
        let point = map(line.0[i], line.1[i])
        if i == 0 || starts?.contains(i) == true { path.move(to: point) } else { path.addLine(to: point) }
    }
    ctx.stroke(path, with: .color(style), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
}

// Draw the spiral up to the given time, filling the space with some padding
func paintDrawing(_ ctx: GraphicsContext, _ size: CGSize, _ d: Prepared, _ upTo: Double, _ palette: Palette) {

    // Scale and center the drawing to fit the space with 16 points of padding
    let w = Double(size.width), h = Double(size.height)
    let pad = 16.0
    let s = min((w - 2 * pad) / or1(d.box.maxX - d.box.minX), (h - 2 * pad) / or1(d.box.maxY - d.box.minY))
    let ox = w / 2 - s * (d.box.minX + d.box.maxX) / 2, oy = h / 2 - s * (d.box.minY + d.box.maxY) / 2
    let map = { (x: Double, y: Double) in CGPoint(x: ox + s * x, y: oy + s * y) }

    // Count how many points were drawn by the given time
    var n = d.raw.0.count
    if upTo < Double.infinity {
        n = 0
        while n < d.t.count && d.t[n] <= upTo { n += 1 }
    }

    // Draw the recorded line faded
    var faded = ctx
    faded.opacity = 0.55
    strokeLine(faded, d.raw, map, n, d.starts, palette.ink2.color, 1.5)

    // Draw the smoothed line on top once every point is shown
    if n == d.raw.0.count { strokeLine(ctx, d.filtered, map, d.filtered.0.count, nil, palette.accent.color, 3) }
}

// Draw the speed chart as a filled area with a line on top
func paintSpeed(_ ctx: GraphicsContext, _ size: CGSize, _ speeds: [Double], _ palette: Palette) {
    let w = Double(size.width), h = Double(size.height)

    // Draw nothing with fewer than 2 speeds
    if speeds.count < 2 { return }

    // Find the fastest speed, using 1 if every speed is slower
    var top = 1.0
    for v in speeds { if v > top { top = v } }

    // Turn a point number into an x position and a speed into a y position
    let X = { (i: Int) in (Double(i) / Double(speeds.count - 1)) * w }, Y = { (v: Double) in h - 4 - (v / top) * (h - 8) }

    // Fill the area under the speeds
    var area = Path()
    area.move(to: CGPoint(x: 0, y: h))
    for (i, v) in speeds.enumerated() { area.addLine(to: CGPoint(x: X(i), y: Y(v))) }
    area.addLine(to: CGPoint(x: w, y: h))
    area.closeSubpath()
    ctx.fill(area, with: .color(palette.accentSoft.color))

    // Draw the line along the top of the area
    var line = Path()
    for (i, v) in speeds.enumerated() {
        if i == 0 { line.move(to: CGPoint(x: X(i), y: Y(v))) } else { line.addLine(to: CGPoint(x: X(i), y: Y(v))) }
    }
    ctx.stroke(line, with: .color(palette.accent.color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
}


// THE RESULTS MODEL

// Holds what the results screen needs, and handles picking and replaying spirals
@MainActor
@Observable
final class ResultsModel {

    // The main app model
    unowned let app: AppModel

    // The check in being shown, and a number that goes up each time it is shown again
    var rec: AssessmentRecord? = nil
    var renderID = 0

    // Which spiral is picked, and how many spirals have drawings
    var which = 0
    var drawnCount = 0

    // The picked spiral ready to draw, and the time it is drawn up to
    var prepared: Prepared? = nil
    var upTo = Double.infinity

    // The replay animation frame
    @ObservationIgnored private var frame = 0

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // Load the check in to show when the screen shows
    func onShow(_ id: String?) {
        rec = nil

        // With an id, load that check in, or go to the dashboard if it has no result
        if let id {
            Task {
                let found = try? await Store.getAssessment(Int(id) ?? -1)
                guard let found, found.result != nil else { return app.go(.dashboard) }
                app.current = found
                renderResults(found)
            }
            return
        }

        // Without an id, show the current check in
        if let current = app.current { renderResults(current) }
    }

    // Show a check in and get its first drawing ready
    private func renderResults(_ rec: AssessmentRecord) {
        self.rec = rec
        renderID += 1
        drawingCard(rec)
    }

    // The spirals in the check in that have recorded points
    private func drawn() -> [AssessmentTrial] { (rec?.trials ?? []).filter { t in t.samples != nil } }

    // Reset the drawing and get the first spiral ready
    private func drawingCard(_ rec: AssessmentRecord) {

        // Stop any replay and go back to the first spiral
        Frames.cancel(frame)
        upTo = .infinity
        which = 0
        prepared = nil

        // Count the spirals and stop if there are none
        let trials = drawn()
        drawnCount = trials.count
        guard let trial = trials.first else { return }

        // Get the first spiral ready, or print an error if it fails
        do {
            prepared = try prepareDrawing(trial)
        } catch {
            print("NeuroTrace: couldn't prepare the drawing", error)
        }
    }

    // Show the spiral at the given number
    func pick(_ i: Int) {

        // Stop if there is no spiral at that number
        let trials = drawn()
        if i >= trials.count { return }

        // Get that spiral ready, or print an error and stop if it fails
        do {
            prepared = try prepareDrawing(trials[i])
        } catch {
            return print("NeuroTrace: couldn't prepare that spiral", error)
        }

        // Pick it, stop any replay and show the whole drawing
        which = i
        Frames.cancel(frame)
        upTo = .infinity
    }

    // Draw the spiral again at the speed it was drawn
    func replayDrawing() {
        guard let prepared, let end = prepared.t.last else { return }
        Frames.cancel(frame)
        let start = Frames.now()

        // Each frame, show the points drawn so far, and ask for another frame until the end
        func step(_ now: Double) {
            let elapsed = (now - start) / 1000
            upTo = elapsed >= end ? .infinity : elapsed
            if elapsed < end { frame = Frames.next(step) }
        }
        frame = Frames.next(step)
    }
}


// THE PARTS OF THE SCREEN

// A card with a title on top of its content
struct ResultCard<Content: View>: View {

    // The title and what goes in the card
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Card {
            Text(title).text(.cardTitle)
            content()
        }
    }
}

// Split a measure's sentence into the text before the percent, the number, and the text after it
private func measureParts(_ key: String, _ frac: Double) -> (lead: String, n: Int, tail: String) {
    let sentence = Copy.measureSentence(key, frac)

    // Give back the whole sentence if it has no percent in it
    guard let hit = sentence.range(of: #"\d+%"#, options: .regularExpression) else { return (sentence, 0, "") }
    let digits = sentence[hit].dropLast()
    return (String(sentence[..<hit.lowerBound]), Int(digits) ?? 0, "%" + String(sentence[hit.upperBound...]))
}

// One measure with its name, its sentence and a dot on a track
struct MeasureRow: View {

    // The measure, where it sits from 0 to 1, its place in the reveal order, and if it sits in a group
    let key: String
    let frac: Double
    let index: Int
    var grouped = false

    // The colors and text sizes
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    // The number shown while counting up, and if the row has been revealed
    @State private var shown: Int? = nil
    @State private var revealed = false

    var body: some View {
        let parts = measureParts(key, frac)
        let font = NTFont.body(15, lineHeight: 1.4)
        VStack(alignment: .leading, spacing: 4) {

            // The name of the measure
            Text(Copy.measures[key]?.name ?? key).text(.strong)

            // The sentence with the counting number in the middle
            (ntText(parts.lead, font, typo) + ntText("\(shown ?? parts.n)", font, typo).monospacedDigit() + ntText(parts.tail, font, typo))
                .lineSpacing(lineGap(font, typo))
                .foregroundStyle(p.ink2.color)
                .fixedSize(horizontal: false, vertical: true)

            // The track with one dot on it
            Track(dots: [(frac: frac, then: false)], active: revealed)
        }
        .fullWidth()
        .padding(.top, grouped ? 10 : 14)
        // A thin line on top when the row is not in a group
        .overlay(alignment: .top) { if !grouped { Hairline() } }
        // On reveal, light up the track and count the number up
        .reveal(index) {
            revealed = true
            Motion.countUp(parts.n) { v in shown = v }
        }
    }
}

// Where the combined model result sits among the healthy reference group, counted up on reveal
private struct ModelScore: View {

    // The result from 0 to 1, the size of the reference group, and its place in the reveal order
    let scorePct: Double
    let referenceN: Int
    let index: Int

    // The colors, and the number shown while counting up
    @Environment(\.palette) private var p
    @State private var shown: Int? = nil

    var body: some View {
        let pct = Int(jsRound(scorePct * 100))

        // The big percent on top and the sentence underneath
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
        // Screen readers read the percent and the sentence together
        .accessibilityElement()
        .accessibilityLabel("\(pct)% \(Copy.modelScoreSentence(referenceN: referenceN))")
        // Count the number up from 0 on reveal
        .reveal(index) { Motion.countUp(pct, from: 0) { v in shown = v } }
    }
}

// One measure's share of the model's result, shown as a bar
private struct ContribRow: View {

    // The bar from Score.contributionBars, and its place in the reveal order
    let bar: Score.Bar
    let index: Int

    // The colors, and if the bar has grown in
    @Environment(\.palette) private var p
    @State private var grown = false

    var body: some View {
        let name = Copy.measures[bar.key]?.name ?? bar.key
        let effect = bar.raises ? Copy.contribRaised : Copy.contribLowered
        return VStack(alignment: .leading, spacing: 4) {

            // The measure name, and if it raised or lowered the result
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).text(.strong)
                Spacer(minLength: 0)
                Text(effect).text(.sub)
            }

            // A gray track with the bar growing across it, at least 3 points wide
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
        // Screen readers read the name and the effect together
        .accessibilityElement()
        .accessibilityLabel("\(name), \(effect)")
        // Grow the bar on reveal
        .reveal(index) { grown = true }
    }
}

// The three result levels side by side, with the current one filled in
private struct Levels: View {

    // The current level from 0 to 2
    let tier: Int

    // The colors, and if the current level has filled in
    @Environment(\.palette) private var p
    @State private var filled = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                let on = i == tier

                // A bar and a short name for each level, in color and bold for the current one
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
        // Screen readers read the levels as one line
        .accessibilityElement()
        .accessibilityLabel("Result level: \(Copy.tierShort[tier]), \(tier + 1) of 3")
        // Fill in the current level when it shows
        .onAppear {

            // With Reduced Motion on, fill it in right away
            if Motion.reduced() {
                filled = true
                return
            }

            // Grow the bar in after a short pause
            withAnimation(Theme.ease(760).delay(0.26)) { filled = true }
        }
    }
}

// The card with the drawing, the replay button and the speed chart
private struct DrawingCard: View {

    // The app model and the colors
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let m = app.results

        // With a prepared spiral, show the full drawing card
        if let prepared = m.prepared {
            ResultCard(title: "Your drawing") {

                // With more than one spiral, show buttons to pick one
                if m.drawnCount > 1 {
                    Segmented(
                        options: (0..<m.drawnCount).map { i in (value: "\(i)", label: "Spiral \(i + 1)") },
                        selected: "\(m.which)"
                    ) { value, _ in m.pick(Int(value) ?? 0) }
                    .accessibilityLabel("Which spiral to show")
                }

                // The drawing in a square
                Canvas { ctx, size in paintDrawing(ctx, size, prepared, m.upTo, p) }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 320)
                    .fullWidth(.center)
                    .accessibilityElement()
                    .accessibilityLabel("Your recorded line drawn under the smoothed version the measures are taken from")
                    .accessibilityAddTraits(.isImage)

                // The key for the recorded line and the smoothed line
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

                // The replay button and a thin line under it
                Btn(title: "Replay drawing", kind: .secondary, icon: .play, compact: true) { m.replayDrawing() }
                Hairline().padding(.vertical, 6)

                // The speed chart with its title and caption
                Text("Speed along the line").text(.h3)
                Text(Copy.speedCaption).text(.sub)
                Canvas { ctx, size in paintSpeed(ctx, size, prepared.speeds, p) }
                    .frame(height: 88)
                    .accessibilityElement()
                    .accessibilityLabel("Drawing speed over time")
                    .accessibilityAddTraits(.isImage)
            }
        } else if let rec = m.rec, let path = checkinPath(rec), !path.t.isEmpty {

            // With only the saved replay copy, show that drawing and a note
            ResultCard(title: "Your drawing") {
                Canvas { ctx, size in paintPath(ctx, size, path, .infinity, p) }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 320)
                    .fullWidth(.center)
                    .accessibilityElement()
                    .accessibilityLabel("Your spiral from \(whenText(rec.ts))")
                    .accessibilityAddTraits(.isImage)
                Text(Copy.drawingPruned).text(.sub).fixedSize(horizontal: false, vertical: true)
            }
        } else {

            // With no drawing at all, show a note
            ResultCard(title: "Your drawing") {
                Text(Copy.replayMissing).text(.sub)
            }
        }
    }
}

// All the result cards for one check in
private struct ResultsBody: View {

    // The check in and its result
    let rec: AssessmentRecord
    let result: Score.Result

    // The text sizes and colors
    @Environment(\.typo) private var typo
    @Environment(\.palette) private var p

    // True when the result has a value for the measure
    private func shown(_ k: String) -> Bool { result.measurePct[k] != nil }

    // The measures that pushed the result up, that have a value
    private var stoodOutKeys: [String] { Score.pushedUp(result).filter { k in shown(k) } }

    // The groups of measures in order, each with the measures that have a value, leaving out empty groups
    private var groups: [(group: Copy.Group, keys: [String])] {
        Copy.groups.compactMap { g in
            let keys = NTFeatures.spiralFeatureOrder.filter { k in Copy.measures[k]?.group == g.id && shown(k) }
            return keys.isEmpty ? nil : (group: g, keys: keys)
        }
    }

    var body: some View {
        let tier = Copy.tiers[result.tier]

        // On wide screens, show the cards in two columns
        if typo.width >= 900 {
            HStack(alignment: .top, spacing: 32) {

                // The left column with the summary, levels, meaning, what to do and the drawing
                VStack(alignment: .leading, spacing: 0) {
                    summary.reveal(0)
                    Levels(tier: result.tier).reveal(1)
                    reference.reveal(2)
                    meaning(tier).padding(.top, 28).reveal(3)
                    todo(tier).padding(.top, 16).reveal(6)
                    DrawingCard().padding(.top, 16).reveal(7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The right column with what stood out, the model card and every measure
                VStack(alignment: .leading, spacing: 0) {
                    stoodOut.reveal(4)
                    modelCard(5).padding(.top, 16)
                    every.padding(.top, 16).reveal(8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {

            // On narrow screens, show all the cards in one column
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

    // The summary sentence in bold at the top
    private var summary: some View {
        Text(Copy.resultSummary)
            .nt(.body(19, 600, lineHeight: 1.45))
            .foregroundStyle(p.ink.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    // The sentence about who you are compared with
    private var reference: some View {
        Text(Copy.referenceSentence(referenceN: result.referenceN, bracketKey: result.bracketKey, deviceMatched: result.deviceMatched))
            .text(.sub)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 18)
    }

    // The What this means card, one paragraph per line of the level's text
    private func meaning(_ tier: Copy.Tier) -> some View {
        ResultCard(title: "What this means") {
            ForEach(0..<tier.meaning.count, id: \.self) { i in
                Text(tier.meaning[i]).text(.body).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // The What you can do card
    private func todo(_ tier: Copy.Tier) -> some View {
        ResultCard(title: "What you can do") {
            Text(tier.todo).text(.body).fixedSize(horizontal: false, vertical: true)
        }
    }

    // The What stood out card
    private var stoodOut: some View {
        ResultCard(title: "What stood out") {

            // With nothing that pushed the result up, show a note
            if stoodOutKeys.isEmpty {
                Text(Copy.nothingPushedUp).text(.body).fixedSize(horizontal: false, vertical: true)
            } else {

                // Otherwise show a caption and a row for each measure that pushed it up
                Text(Copy.stoodOutCaption).text(.sub)
                ForEach(0..<stoodOutKeys.count, id: \.self) { i in
                    MeasureRow(key: stoodOutKeys[i], frac: result.measurePct[stoodOutKeys[i]] ?? 0, index: i)
                }
            }
        }
    }

    // The How the model read it card, starting the reveal order at base
    private func modelCard(_ base: Int) -> some View {
        let bars = Score.contributionBars(result)
        return ResultCard(title: "How the model read it") {

            // The caption, the model's percent and the disclaimer
            Text(Copy.modelCardCaption).text(.sub).fixedSize(horizontal: false, vertical: true)
            ModelScore(scorePct: result.scorePct, referenceN: result.referenceN, index: base)
            Text(Copy.modelDisclaimer).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 2)

            // A caption and a bar for each measure's share, when there are any
            if !bars.isEmpty {
                Text(Copy.contribCaption).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
                ForEach(0..<bars.count, id: \.self) { i in
                    ContribRow(bar: bars[i], index: base + i)
                }
            }

            // A thin line, then the model note, adding the training note when the device did not match
            Hairline().padding(.vertical, 8)
            Text(Copy.modelNote + (result.deviceMatched ? "" : " " + Copy.referenceInTraining)).text(.sub).fixedSize(horizontal: false, vertical: true)
        }
    }

    // The Every measure card, with the measures in their groups
    private var every: some View {

        // Start the reveal order after the What stood out rows
        let first = stoodOutKeys.count
        let groups = self.groups

        // Count how many measures come before each group
        let offsets = groups.indices.map { g in groups[..<g].reduce(0) { n, entry in n + entry.keys.count } }
        return ResultCard(title: "Every measure") {

            // The caption and the Lowest, Halfway and Highest labels over the tracks
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

            // Each group with its title, description and measure rows, with a thin line on top
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


// THE SCREEN

// The results screen itself
struct ResultsScreen: View {

    // The app model and the text sizes
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.results

        // Use a wider page on wide screens
        ScreenView(maxWidth: typo.width >= 900 ? 1040 : 560, titled: true) { _ in

            // The date of the check in and the Done link at the top
            HStack(spacing: 12) {
                Text(m.rec.map { r in "Spiral check-in · \(whenText(r.ts))" } ?? "").text(.sub)
                Spacer(minLength: 0)
                BarLink(label: "Done", strong: true) { app.go(.dashboard) }
            }
            .frame(minHeight: 44)

            // The name of the result level as the headline
            H1(text: m.rec?.result.map { r in Copy.tiers[r.tier].label } ?? "", size: 32, lineHeight: 1.12, top: 14)

            // All the result cards, once the check in has a result
            if let rec = m.rec, let result = rec.result {
                ResultsBody(rec: rec, result: result).id(m.renderID)
            }

            // The Check again and Done buttons at the bottom
            HStack(spacing: 12) {
                Btn(title: "Check again", kind: .secondary) { app.go(.about) }
                Btn(title: "Done") { app.go(.dashboard) }
            }
            .padding(.top, 52)
        }
    }
}
