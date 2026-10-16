import SwiftUI
import UIKit

private let dateFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("MMMd")
    return format
}()

private func parseISO(_ text: String) -> Date? {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}

private func jsNumber(_ text: String) -> Double {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return 0 }
    return Double(trimmed) ?? .nan
}

@MainActor
@Observable
final class CollectModel {
    unowned let app: AppModel
    static let collectTrials = 3

    var pendingId = ""
    var subs: [Store.Subject] = []
    var waiting = 0

    var consent = false
    var ageText = ""
    var medText = ""
    var hand: String? = nil
    var dx: String? = nil

    var count = "Spiral 1 of 3"
    var progressDone = 0
    var trialID = 0
    var nextLabel = "Next spiral"
    var nextDisabled = true
    var status: String? = nil
    let shaker = Shaker()
    @ObservationIgnored private var inert = false
    // How many times the spiral being drawn now has been sent back by SpiralCheck
    @ObservationIgnored private var redos = 0
    // True while a share sheet is up, so a second tap doesn't open another
    @ObservationIgnored private var exporting = false

    @ObservationIgnored lazy var pad: Pad = createPad(onInk: { [weak self] cleared in self?.onInk(cleared) })

    init(app: AppModel) { self.app = app }

    private func startSession(_ subjectId: String, _ session: Int) {
        app.collecting = Collecting(subjectId: subjectId, session: session)
        app.go(.collectDetails)
    }

    func onShow() {
        // Cleared straight away, so a session started before the list loads isn't wiped when it does.
        // Start stays off until the new ID is ready
        app.collecting = nil
        pendingId = ""
        Task {
            var subs: [Store.Subject] = [], sessions: [CollectedSession] = []
            do {
                subs = try await Store.subjects()
                sessions = try await Store.listCollected()
            } catch {
                print("NeuroTrace: couldn't read collected sessions", error)
            }
            pendingId = Store.newSubjectId(Set(subs.map { s in s.subjectId }))
            self.subs = subs
            waiting = sessions.filter { s in !s.exported }.count
        }
    }

    func start() {
        if pendingId.isEmpty { return }
        startSession(pendingId, 1)
    }

    func resume(_ subject: Store.Subject) { startSession(subject.subjectId, subject.sessions + 1) }

    func exportAll() async {
        if exporting { return }
        exporting = true
        defer { exporting = false }
        let waiting = ((try? await Store.listCollected()) ?? []).filter { s in !s.exported }
        if waiting.isEmpty { return }
        let day = String(isoNow().prefix(10))
        if await exportSessions(waiting, "neurotrace-export-\(day).json") { onShow() }
    }

    func readDetails() -> CollectDetails {
        let age = jsNumber(ageText)
        let med = medText
        let dx = self.dx
        return CollectDetails(
            consent: consent,
            age: age.rounded() == age && age >= 18 && age <= 110 ? Int(age) : nil,
            hand: hand,
            diagnosis: dx,
            medicationHoursAgo: dx == "parkinsons" && med != "" && jsNumber(med) >= 0 ? jsNumber(med) : nil
        )
    }

    var missing: [String] {
        let d = readDetails()
        return [!d.consent ? "consent" : nil, d.age == nil ? "an age from 18 to 110" : nil, d.hand == nil ? "the drawing hand" : nil, d.diagnosis == nil ? "a diagnosis" : nil].compactMap { $0 }
    }

    var bracket: String { readDetails().age.map { a in Copy.bracketNote(a) } ?? "" }

    func onShowDetails() {
        if app.collecting?.details != nil { return }
        consent = false
        ageText = ""
        medText = ""
        hand = nil
        dx = nil
    }

    func begin() {
        app.collecting?.details = readDetails()
        app.collecting?.trials = []
        app.go(.collectDraw)
    }

    private func onInk(_ cleared: String?) {
        nextDisabled = inert || !pad.hasInk()
        showStatus(cleared != nil ? Copy.resizeCleared : nil)
        if cleared != nil { pad.showStartDot(true) }
    }

    private func setInert(_ on: Bool) {
        inert = on
        pad.isUserInteractionEnabled = !on
    }

    private func showStatus(_ sentence: String?) {
        status = sentence
        guard let sentence else { return }
        shaker.shake()
        UIAccessibility.post(notification: .announcement, argument: sentence)
    }

    func newCollectTrial() {
        let done = app.collecting?.trials.count ?? 0
        count = "Spiral \(done + 1) of \(CollectModel.collectTrials)"
        progressDone = done
        trialID += 1
        redos = 0
        nextLabel = done + 1 == CollectModel.collectTrials ? "Finish" : "Next spiral"
        pad.reset()
        pad.showStartDot(true)
        setInert(false)
        nextDisabled = true
        showStatus(nil)
    }

    func onShowDraw() {
        if app.collecting?.details == nil { return app.go(.collectDetails) }
        app.collecting?.trials = []
        newCollectTrial()
    }

    func back() async {
        // Waits while a spiral is being measured or the session is saving
        if inert { return }
        let drawnSome = (app.collecting?.trials.count ?? 0) > 0 || pad.hasInk()
        if drawnSome {
            if !(await confirm(Copy.leaveSession, Copy.leaveSessionDetail, action: "Leave")) { return }
        }
        app.go(.collectDetails)
    }

    func next() async {
        // A second tap before the screen catches up does nothing, so one spiral can't be saved twice
        if inert || nextDisabled { return }
        guard let details = app.collecting?.details else { return }
        let trace = pad.trace(details.hand)
        let trial = trialID
        // The pad rests while the spiral is measured, and the screen keeps moving
        setInert(true)
        nextDisabled = true
        let measured = try? await JSCore.background { try NTFeatures.featuresFromTrace(trace) }
        // Redo this spiral while it was being measured means this one doesn't count
        if trialID != trial || app.screen != .collectDraw { return }
        guard let features = measured else {
            setInert(false)
            nextDisabled = !pad.hasInk()
            return showStatus(Copy.tooShort)
        }
        // A scribble would throw off the reference group, so it's sent back. A facilitator is watching here,
        // so after a couple of redos the spiral is kept as a real attempt
        if let problem = SpiralCheck.problem(features), redos < SpiralCheck.hintAfter {
            redos += 1
            setInert(false)
            pad.reset()
            pad.showStartDot(true)
            nextDisabled = true
            return showStatus(problem == .offGuide ? Copy.spiralOffGuide : Copy.spiralTooFast)
        }
        app.collecting?.trials.append(trace)
        vibrate(12)
        let drawn = app.collecting?.trials.count ?? 0
        if drawn < CollectModel.collectTrials {
            Motion.toast(Copy.spiralSaved(drawn))
            return newCollectTrial()
        }

        nextDisabled = true
        setInert(true)
        guard let collecting = app.collecting else { return }
        let traces = collecting.trials
        var record = CollectedSession(
            id: nil,
            formatVersion: 1,
            subjectId: collecting.subjectId,
            session: collecting.session,
            collectedAt: isoNow(),
            deviceLabel: traces[0].deviceLabel,
            inputType: traces[0].inputType,
            hand: details.hand ?? "",
            age: details.age,
            diagnosis: details.diagnosis ?? "",
            medicationHoursAgo: details.medicationHoursAgo,
            consent: true,
            trials: traces.enumerated().map { (i, tr) in
                CollectedTrial(trial: i + 1, task: "spiral", samples: tr.samples.map { s in CollectedSample(t: s.t, x: s.x, y: s.y, pressure: s.pressure) })
            },
            exported: false
        )
        do {
            record.id = try await Store.saveCollected(record)
        } catch {
            print("NeuroTrace: couldn't save the session on this iPad", error)
        }
        app.collecting?.saved = record
        app.go(.collectDone)
    }

    func onShowDone() {
        if app.collecting?.saved == nil { app.go(.collect) }
    }

    func exportDone() async {
        if exporting { return }
        exporting = true
        defer { exporting = false }
        if let s = app.collecting?.saved { _ = await exportSessions([s], "\(s.subjectId)-s\(s.session).json") }
    }
}

@MainActor
func exportSessions(_ sessions: [CollectedSession], _ filename: String) async -> Bool {
    let data = sessions.count == 1 ? jsonForExport(sessions[0], pretty: true) : jsonForExport(sessions, pretty: true)
    if !(await shareFile(ExportFile(name: filename, data: data))) { return false }
    let ids = sessions.compactMap { s in s.id }
    if !ids.isEmpty {
        do {
            try await Store.markExported(ids)
        } catch {
            print("NeuroTrace: couldn't mark sessions exported", error)
        }
    }
    Motion.toast(Copy.exported)
    return true
}

private struct TopBar: View {
    var topInset: CGFloat
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                MarkView(size: 22, color: Color(red: 0xf5 / 255, green: 0xf5 / 255, blue: 0xf7 / 255))
                Text("NeuroTrace").nt(.body(15, 600, lineHeight: 1.4)).foregroundStyle(Color(red: 0xf5 / 255, green: 0xf5 / 255, blue: 0xf7 / 255))
                Text("Collection mode").foregroundStyle(Color(red: 0xa1 / 255, green: 0xa1 / 255, blue: 0xa6 / 255))
            }
            Spacer(minLength: 0)
            Button {
                app.go(.settings)
            } label: {
                Text("Exit")
                    .foregroundStyle(Color(red: 0x29 / 255, green: 0x97 / 255, blue: 0xff / 255))
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .nt(.body(15, lineHeight: 1.4))
        .padding(.horizontal, 32)
        .padding(.top, topInset)
        .frame(minHeight: 52 + topInset)
        .background(Color.black)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }
}

private struct CollectFrame<Content: View>: View {
    var padTop: CGFloat = 20
    var centered = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            VStack(spacing: 0) {
                TopBar(topInset: insets.top)
                ScrollView(.vertical) {
                    VStack(alignment: centered ? .center : .leading, spacing: 0) { content() }
                        .multilineTextAlignment(centered ? .center : .leading)
                        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                        .padding(.top, padTop)
                        .padding(.leading, max(insets.leading, 24))
                        .padding(.trailing, max(insets.trailing, 24))
                        .padding(.bottom, max(insets.bottom, 40))
                        .frame(maxWidth: 760)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height + insets.bottom - 52, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .ignoresSafeArea(.container)
        }
        .environment(\.collectMode, true)
    }
}

private struct CollectTypography: ViewModifier {
    @Environment(\.typo) private var typo

    func body(content: Content) -> some View {
        var t = typo
        t.body = 19
        return content.environment(\.typo, t)
    }
}

struct CollectScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.collect
        CollectBody(padTop: 48) {
            H1(text: "Tester collection", size: 44, lineHeight: 1.08, top: 0)
            Text(Copy.collectIntro).text(.lede).frame(maxWidth: 620, alignment: .leading).padding(.top, 14)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: typo.width >= 700 ? 2 : 1)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                Card {
                    Text("New participant").nt(.display(24, 600, lineHeight: 1.2)).foregroundStyle(p.ink.color)
                    Text(Copy.newParticipant).nt(.body(17)).foregroundStyle(p.ink2.color)
                    VStack(spacing: 4) {
                        Text("Participant ID").nt(.body(15, 600, lineHeight: 1.4)).foregroundStyle(p.ink2.color)
                        Text(m.pendingId).nt(.mono(40, 600, lineHeight: 1.2)).tracking(0.08 * 40).foregroundStyle(p.ink.color)
                    }
                    .frame(maxWidth: .infinity, minHeight: 104)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(p.bg.color))
                    Btn(title: "Start session 1", disabled: m.pendingId.isEmpty) { m.start() }
                }
                Card {
                    Text("Returning").nt(.display(24, 600, lineHeight: 1.2)).foregroundStyle(p.ink.color)
                    Text(Copy.returningBlurb).nt(.body(17)).foregroundStyle(p.ink2.color)
                    if m.subs.isEmpty {
                        Text(Copy.noParticipants).text(.sub)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(m.subs, id: \.subjectId) { s in
                                HistoryRow(when: s.subjectId, sub: "\(s.sessions) session\(s.sessions == 1 ? "" : "s"), last on \(parseISO(s.lastAt).map { d in dateFmt.string(from: d) } ?? s.lastAt)", mono: true) {
                                    m.resume(s)
                                }
                                .overlay(alignment: .top) { Hairline() }
                            }
                        }
                    }
                }
            }
            .padding(.top, 36)

            if m.waiting > 0 {
                Card {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 24) { exportText(m.waiting); Spacer(minLength: 0); exportButton(m) }
                        VStack(alignment: .leading, spacing: 16) { exportText(m.waiting); exportButton(m) }
                    }
                }
                .padding(.top, 24)
            }
        }
    }

    private func exportText(_ waiting: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(waiting) session\(waiting == 1 ? "" : "s") not exported yet").nt(.display(21, 600, lineHeight: 1.2)).foregroundStyle(p.ink.color)
            Text(Copy.unexportedHelp).nt(.body(17)).foregroundStyle(p.ink2.color)
        }
    }

    private func exportButton(_ m: CollectModel) -> some View {
        Btn(title: "Export all", kind: .secondary) { Task { await m.exportAll() } }.fixedSize()
    }
}

private struct CollectBody<Content: View>: View {
    var padTop: CGFloat = 20
    var centered = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        CollectFrame(padTop: padTop, centered: centered) { content() }
            .modifier(CollectTypography())
    }
}

struct CollectDetailsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let m = app.collect
        let details = m.readDetails()
        let missing = m.missing
        CollectBody {
            HStack(spacing: 12) {
                BackLink { app.go(.collect) }
                Spacer(minLength: 0)
                if let c = app.collecting {
                    Pill(text: Text(c.subjectId).font(.system(size: 15, weight: .semibold, design: .monospaced)) + Text(", session \(c.session)"))
                }
            }
            .frame(minHeight: 44)

            H1(text: "About the participant", size: 40, lineHeight: 1.1, top: 20)

            Card(padding: 0, spacing: 0) {
                CheckRow(text: Copy.collectConsent, checked: m.consent, compact: true) { m.consent.toggle() }
                    .padding(.vertical, 22)
                    .padding(.horizontal, 28)
                Hairline()
                FormRow(label: "Age") {
                    NumberField(text: Binding(get: { m.ageText }, set: { m.ageText = $0 }), decimal: false)
                    Text(m.bracket).text(.sub)
                }
                Hairline()
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Drawing hand")
                    ChipGrid(items: [(value: "left", label: "Left"), (value: "right", label: "Right")], selected: m.hand) { value in m.hand = value }
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 28)
                Hairline()
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Diagnosis")
                    ChipGrid(
                        items: [(value: "none", label: "None"), (value: "parkinsons", label: "Parkinson\u{2019}s"), (value: "essential_tremor", label: "Essential tremor"), (value: "other", label: "Other")],
                        selected: m.dx
                    ) { value in m.dx = value }
                    Text(Copy.diagnosisNote).text(.sub).padding(.top, 10)
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 28)
                if details.diagnosis == "parkinsons" {
                    Hairline()
                    FormRow(label: "Hours since last dose") {
                        NumberField(text: Binding(get: { m.medText }, set: { m.medText = $0 }), decimal: true)
                        Text(Copy.medHelp).text(.sub)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 28)

            Spacer(minLength: 0)
            VStack(spacing: 12) {
                if !missing.isEmpty {
                    Text("Still needed: \(missing.joined(separator: ", ")).").text(.sub).multilineTextAlignment(.center).fullWidth(.center)
                }
                Btn(title: "Begin spirals", disabled: !missing.isEmpty) { m.begin() }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 24)
        }
    }
}

private struct FormRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                Text(label).text(.strong).frame(width: 180, alignment: .leading)
                content()
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(label).text(.strong)
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
    }
}

private struct NumberField: View {
    @Binding var text: String
    var decimal: Bool
    @Environment(\.palette) private var p

    var body: some View {
        TextField("", text: $text)
            .keyboardType(decimal ? .decimalPad : .numberPad)
            .nt(.body(28, 600, lineHeight: 1.2))
            .monospacedDigit()
            .foregroundStyle(p.ink.color)
            .padding(.horizontal, 16)
            .frame(width: 140, height: 60)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.surface.color))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.guide.color, lineWidth: p.hair))
    }
}

struct CollectDrawScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.collect
        CollectBody(centered: true) {
            Bar(side: 160) {
                BackLink { Task { await m.back() } }
            } center: {
                H1(text: m.count, size: 21, lineHeight: 1.3, top: 0, weight: 600)
            } right: {
                if let c = app.collecting {
                    (Text(c.subjectId).font(.system(size: 15, design: .monospaced)) + Text(", session \(c.session)")).text(.sub)
                }
            }
            Segments(total: CollectModel.collectTrials, done: m.progressDone, width: 180, height: 6, gap: 8)
                .id(m.trialID)
                .padding(.top, 8)
            Text(Copy.collectDrawInstruction).text(.lede).frame(maxWidth: 620).padding(.top, 24)
            PadBox(cap: max(min(680, typo.height - 420), 280)) {
                PadView(pad: m.pad)
            }
            .padding(.top, 28)
            StatusBox(sentence: m.status, shake: m.shaker.x).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Btn(title: "Redo this spiral", kind: .secondary, icon: .redo) { m.newCollectTrial() }
                Btn(title: m.nextLabel, disabled: m.nextDisabled) { Task { await m.next() } }
            }
            .frame(maxWidth: 680)
            .padding(.top, 24)
        }
    }
}

struct CollectDoneScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let m = app.collect
        CollectBody(padTop: 96, centered: true) {
            ZStack {
                Circle().fill(p.accentSoft.color)
                IconView(icon: .checkmark, size: 46, weight: 2.4).foregroundStyle(p.accent.color)
            }
            .frame(width: 96, height: 96)
            H1(text: "Session saved", size: 44, lineHeight: 1.08, top: 28)
            Text(Copy.sessionSaved).text(.lede).frame(maxWidth: 560)
            if let s = app.collecting?.saved {
                let facts: [(String, String)] = [
                    ("Participant", s.subjectId),
                    ("Session", String(s.session)),
                    ("Age", s.age.map { String($0) } ?? "Not given"),
                    ("Drawing hand", s.hand == "left" ? "Left" : "Right"),
                    ("Diagnosis", Copy.diagnoses[s.diagnosis] ?? s.diagnosis),
                    ("Input", ["pencil": "Apple Pencil", "touch": "Finger", "mouse": "Mouse"][s.inputType ?? ""] ?? s.inputType ?? "Not recorded"),
                ]
                Card(padding: 0, spacing: 0) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 32, alignment: .leading), GridItem(.flexible(), spacing: 32, alignment: .leading)], alignment: .leading, spacing: 0) {
                        ForEach(0..<facts.count, id: \.self) { i in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(facts[i].0).text(.sub)
                                Text(facts[i].1).nt(.body(19, 600, lineHeight: 1.4)).foregroundStyle(p.ink.color)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 16)
                            .overlay(alignment: .top) { if i >= 2 { Hairline() } }
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 28)
                }
                .frame(maxWidth: 600)
                .padding(.top, 36)
            }
            Spacer(minLength: 0)
            VStack(spacing: 12) {
                Btn(title: "Export session", icon: .export) { Task { await m.exportDone() } }
                Btn(title: "Next participant", kind: .secondary) { app.go(.collect) }
            }
            .frame(maxWidth: 600)
            .padding(.top, 24)
        }
    }
}
