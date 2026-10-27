// COLLECTSCREENS.SWIFT IS COLLECTION MODE, WHERE A TESTER RECORDS SPIRALS FROM PARTICIPANTS ON ONE IPAD
// IT HOLDS THE START SCREEN, THE PARTICIPANT DETAILS FORM, THE DRAWING SCREEN AND THE SESSION SAVED SCREEN
// IT ALSO SAVES EACH SESSION AND EXPORTS SESSIONS AS JSON FILES

import SwiftUI
import UIKit

// Shows dates as a short month and day
private let dateFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("MMMd")
    return format
}()


// Read an ISO date, with or without fractions of a second
private func parseISO(_ text: String) -> Date? {
    let format = ISO8601DateFormatter()
    format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return format.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}


// Turn text into a number the way JavaScript does, with empty text as 0 and anything else that isn't a number as NaN
private func jsNumber(_ text: String) -> Double {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return 0 }
    return Double(trimmed) ?? .nan
}


// Holds what every collection screen needs, and saves and exports the sessions
@MainActor
@Observable
final class CollectModel {

    // The main app model
    unowned let app: AppModel

    // The number of spirals in a session
    static let collectTrials = 3

    // The ID for the next new participant, the participants so far, and how many sessions are not exported yet
    var pendingId = ""
    var subs: [Store.Subject] = []
    var waiting = 0

    // The answers on the details form
    var consent = false
    var ageText = ""
    var medText = ""
    var hand: String? = nil
    var dx: String? = nil

    // What the drawing screen shows, the spiral count, progress, button label and status line
    var count = "Spiral 1 of 3"
    var progressDone = 0
    var trialID = 0
    var nextLabel = "Next spiral"
    var nextDisabled = true
    var status: String? = nil

    // Shakes the status line
    let shaker = Shaker()

    // True while the pad is locked
    @ObservationIgnored private var inert = false

    // How many times the spiral being drawn now has been sent back by SpiralCheck
    @ObservationIgnored private var redos = 0

    // True while a share sheet is up
    @ObservationIgnored private var exporting = false

    // The drawing pad, which calls onInk when the ink changes
    @ObservationIgnored lazy var pad: Pad = createPad(onInk: { [weak self] cleared in self?.onInk(cleared) })

    // Connect the screens to the main app model
    init(app: AppModel) { self.app = app }

    // Start a session for this participant and session number, and open the details form
    private func startSession(_ subjectId: String, _ session: Int) {
        app.collecting = Collecting(subjectId: subjectId, session: session)
        app.go(.collectDetails)
    }


    // THE START SCREEN

    // Load the participants and the sessions not exported when the start screen shows
    func onShow() {

        // Clear the current session and the new ID right away
        app.collecting = nil
        pendingId = ""
        Task {

            // Read the participants and the saved sessions, and print an error if that fails
            var subs: [Store.Subject] = [], sessions: [CollectedSession] = []
            do {
                subs = try await Store.subjects()
                sessions = try await Store.listCollected()
            } catch {
                print("NeuroTrace: couldn't read collected sessions", error)
            }

            // Make a new ID that no participant has, and count the sessions not exported
            pendingId = Store.newSubjectId(Set(subs.map { s in s.subjectId }))
            self.subs = subs
            waiting = sessions.filter { s in !s.exported }.count
        }
    }

    // Start session 1 for the new participant, once the new ID is ready
    func start() {
        if pendingId.isEmpty { return }
        startSession(pendingId, 1)
    }

    // Start the next session for a returning participant
    func resume(_ subject: Store.Subject) { startSession(subject.subjectId, subject.sessions + 1) }

    // Export every session not exported yet into one file named with today's date
    func exportAll() async {

        // Do nothing while a share sheet is already up
        if exporting { return }
        exporting = true
        defer { exporting = false }

        // Find the sessions not exported, and stop if there are none
        let waiting = ((try? await Store.listCollected()) ?? []).filter { s in !s.exported }
        if waiting.isEmpty { return }

        // Share the file, then reload the start screen if it was shared
        let day = String(isoNow().prefix(10))
        if await exportSessions(waiting, "neurotrace-export-\(day).json") { onShow() }
    }


    // THE DETAILS FORM

    // Turn the form answers into details, leaving out an age or dose time that isn't valid
    func readDetails() -> CollectDetails {
        let age = jsNumber(ageText)
        let med = medText
        let dx = self.dx
        return CollectDetails(
            consent: consent,

            // A whole number age from 18 to 110
            age: age.rounded() == age && age >= 18 && age <= 110 ? Int(age) : nil,
            hand: hand,
            diagnosis: dx,

            // Hours after the last dose only for Parkinson's, and only if it is filled in and 0 or more
            medicationHoursAgo: dx == "parkinsons" && med != "" && jsNumber(med) >= 0 ? jsNumber(med) : nil
        )
    }

    // The answers still missing from the form
    var missing: [String] {
        let d = readDetails()
        return [!d.consent ? "consent" : nil, d.age == nil ? "an age from 18 to 110" : nil, d.hand == nil ? "the drawing hand" : nil, d.diagnosis == nil ? "a diagnosis" : nil].compactMap { $0 }
    }

    // The note about the age group, or empty text if there is no valid age
    var bracket: String { readDetails().age.map { a in Copy.bracketNote(a) } ?? "" }

    // Clear the form when it shows, unless this session already has details
    func onShowDetails() {
        if app.collecting?.details != nil { return }
        consent = false
        ageText = ""
        medText = ""
        hand = nil
        dx = nil
    }

    // Save the details, clear the spirals and open the drawing screen
    func begin() {
        app.collecting?.details = readDetails()
        app.collecting?.trials = []
        app.go(.collectDraw)
    }


    // THE DRAWING SCREEN

    // Update the screen when the ink on the pad changes
    private func onInk(_ cleared: String?) {

        // Turn on the next button only when the pad is unlocked and has ink
        nextDisabled = inert || !pad.hasInk()

        // If the drawing was cleared, say so and show the start dot again
        showStatus(cleared != nil ? Copy.resizeCleared : nil)
        if cleared != nil { pad.showStartDot(true) }
    }

    // Lock or unlock the pad
    private func setInert(_ on: Bool) {
        inert = on
        pad.isUserInteractionEnabled = !on
    }

    // Show a sentence in the status line, shake it and read it out, or clear it with nil
    private func showStatus(_ sentence: String?) {
        status = sentence
        guard let sentence else { return }
        shaker.shake()
        UIAccessibility.post(notification: .announcement, argument: sentence)
    }

    // Set up the screen for the next spiral
    func newCollectTrial() {

        // Update the spiral count, the progress bar and the next button label
        let done = app.collecting?.trials.count ?? 0
        count = "Spiral \(done + 1) of \(CollectModel.collectTrials)"
        progressDone = done
        trialID += 1
        redos = 0
        nextLabel = done + 1 == CollectModel.collectTrials ? "Finish" : "Next spiral"

        // Clear the pad, show the start dot, unlock the pad and clear the status line
        pad.reset()
        pad.showStartDot(true)
        setInert(false)
        nextDisabled = true
        showStatus(nil)
    }

    // Start the first spiral when the drawing screen shows, or go to the form if there are no details yet
    func onShowDraw() {
        if app.collecting?.details == nil { return app.go(.collectDetails) }
        app.collecting?.trials = []
        newCollectTrial()
    }

    // Go back to the details form
    func back() async {

        // Do nothing while the pad is locked
        if inert { return }

        // If any spiral was drawn, ask before leaving
        let drawnSome = (app.collecting?.trials.count ?? 0) > 0 || pad.hasInk()
        if drawnSome {
            if !(await confirm(Copy.leaveSession, Copy.leaveSessionDetail, action: "Leave")) { return }
        }
        app.go(.collectDetails)
    }

    // Measure and keep the spiral on the pad, then start the next one or save the session
    func next() async {

        // Do nothing while the pad is locked or the button is off
        if inert || nextDisabled { return }
        guard let details = app.collecting?.details else { return }
        let trace = pad.trace(details.hand)
        let trial = trialID

        // Lock the pad and measure the spiral in the background
        setInert(true)
        nextDisabled = true
        let measured = try? await JSCore.background { try NTFeatures.featuresFromTrace(trace) }

        // Stop if the spiral was redone or the screen changed during measuring
        if trialID != trial || app.screen != .collectDraw { return }

        // If it could not be measured, unlock the pad and show the too short message
        guard let features = measured else {
            setInert(false)
            nextDisabled = !pad.hasInk()
            return showStatus(Copy.tooShort)
        }

        // If SpiralCheck finds a problem, clear the pad and show the message, up to SpiralCheck.hintAfter times
        if let problem = SpiralCheck.problem(features), redos < SpiralCheck.hintAfter {
            redos += 1
            setInert(false)
            pad.reset()
            pad.showStartDot(true)
            nextDisabled = true
            return showStatus(problem == .offGuide ? Copy.spiralOffGuide : Copy.spiralTooFast)
        }

        // Keep the spiral and buzz
        app.collecting?.trials.append(trace)
        vibrate(12)

        // If more spirals are needed, show a saved message and start the next one
        let drawn = app.collecting?.trials.count ?? 0
        if drawn < CollectModel.collectTrials {
            Motion.toast(Copy.spiralSaved(drawn))
            return newCollectTrial()
        }

        // Lock the pad and build the session record from the details and the spirals
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

        // Save the session, and print an error if that fails
        do {
            record.id = try await Store.saveCollected(record)
        } catch {
            print("NeuroTrace: couldn't save the session on this iPad", error)
        }

        // Keep the saved record and open the session saved screen
        app.collecting?.saved = record
        app.go(.collectDone)
    }


    // THE SESSION SAVED SCREEN

    // Go to the start screen if no session was saved
    func onShowDone() {
        if app.collecting?.saved == nil { app.go(.collect) }
    }

    // Export the saved session into a file named with the participant ID and session number
    func exportDone() async {

        // Do nothing while a share sheet is already up
        if exporting { return }
        exporting = true
        defer { exporting = false }
        if let s = app.collecting?.saved { _ = await exportSessions([s], "\(s.subjectId)-s\(s.session).json") }
    }
}


// Share sessions as a JSON file and mark them exported, giving back false if the file wasn't shared
@MainActor
func exportSessions(_ sessions: [CollectedSession], _ filename: String) async -> Bool {

    // Make the JSON, with one session on its own or a list of sessions, and share it
    let data = sessions.count == 1 ? jsonForExport(sessions[0], pretty: true) : jsonForExport(sessions, pretty: true)
    if !(await shareFile(ExportFile(name: filename, data: data))) { return false }

    // Mark the saved sessions exported, and print an error if that fails
    let ids = sessions.compactMap { s in s.id }
    if !ids.isEmpty {
        do {
            try await Store.markExported(ids)
        } catch {
            print("NeuroTrace: couldn't mark sessions exported", error)
        }
    }

    // Show the exported message
    Motion.toast(Copy.exported)
    return true
}


// THE LAYOUT SHARED BY EVERY COLLECTION SCREEN

// The black bar at the top of every collection screen
private struct TopBar: View {

    // The height of the safe area at the top of the screen
    var topInset: CGFloat

    // The main app model
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 16) {

            // The logo, the app name and "Collection mode"
            HStack(spacing: 10) {
                MarkView(size: 22, color: Color(red: 0xf5 / 255, green: 0xf5 / 255, blue: 0xf7 / 255))
                Text("NeuroTrace").nt(.body(15, 600, lineHeight: 1.4)).foregroundStyle(Color(red: 0xf5 / 255, green: 0xf5 / 255, blue: 0xf7 / 255))
                Text("Collection mode").foregroundStyle(Color(red: 0xa1 / 255, green: 0xa1 / 255, blue: 0xa6 / 255))
            }
            Spacer(minLength: 0)

            // The blue Exit button that opens settings
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
        // A thin line along the bottom
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }
}


// The top bar with a scrolling page under it
private struct CollectFrame<Content: View>: View {

    // The space above the content, whether the content is centered, and the content
    var padTop: CGFloat = 20
    var centered = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            VStack(spacing: 0) {

                // The top bar
                TopBar(topInset: insets.top)

                // The content in a scroll view, at most 760 points wide and at least as tall as the screen
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
        // Tell the views inside that they are in collection mode
        .environment(\.collectMode, true)
    }
}


// Sets the body text size to 19 for the views inside
private struct CollectTypography: ViewModifier {

    // The text sizes
    @Environment(\.typo) private var typo

    func body(content: Content) -> some View {
        var t = typo
        t.body = 19
        return content.environment(\.typo, t)
    }
}


// THE SCREENS

// The start screen for a new or returning participant
struct CollectScreen: View {

    // The app model, colors and text sizes
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.collect
        CollectBody(padTop: 48) {

            // The title and the intro
            H1(text: "Tester collection", size: 44, lineHeight: 1.08, top: 0)
            Text(Copy.collectIntro).text(.lede).frame(maxWidth: 620, alignment: .leading).padding(.top, 14)

            // Two cards side by side on screens 700 points wide or more, and one above the other otherwise
            let columns = Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: typo.width >= 700 ? 2 : 1)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {

                // The new participant card with the new ID and the start button
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

                // The returning card with a row for each participant
                Card {
                    Text("Returning").nt(.display(24, 600, lineHeight: 1.2)).foregroundStyle(p.ink.color)
                    Text(Copy.returningBlurb).nt(.body(17)).foregroundStyle(p.ink2.color)

                    // A note when there are no participants yet
                    if m.subs.isEmpty {
                        Text(Copy.noParticipants).text(.sub)
                    } else {

                        // Each row shows the ID, the number of sessions and the last date, and starts the next session when tapped
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

            // A card with the number of sessions not exported and an Export all button, when there are any
            if m.waiting > 0 {
                Card {

                    // The text and button in a row if they fit, and stacked if not
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 24) { exportText(m.waiting); Spacer(minLength: 0); exportButton(m) }
                        VStack(alignment: .leading, spacing: 16) { exportText(m.waiting); exportButton(m) }
                    }
                }
                .padding(.top, 24)
            }
        }
    }

    // The number of sessions not exported and a help line
    private func exportText(_ waiting: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(waiting) session\(waiting == 1 ? "" : "s") not exported yet").nt(.display(21, 600, lineHeight: 1.2)).foregroundStyle(p.ink.color)
            Text(Copy.unexportedHelp).nt(.body(17)).foregroundStyle(p.ink2.color)
        }
    }

    // The Export all button
    private func exportButton(_ m: CollectModel) -> some View {
        Btn(title: "Export all", kind: .secondary) { Task { await m.exportAll() } }.fixedSize()
    }
}


// The collection frame with the larger body text
private struct CollectBody<Content: View>: View {

    // The space above the content, whether the content is centered, and the content
    var padTop: CGFloat = 20
    var centered = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        CollectFrame(padTop: padTop, centered: centered) { content() }
            .modifier(CollectTypography())
    }
}


// The form for the participant's details
struct CollectDetailsScreen: View {

    // The app model and colors
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let m = app.collect
        let details = m.readDetails()
        let missing = m.missing
        CollectBody {

            // The back link, and a pill with the participant ID and session number
            HStack(spacing: 12) {
                BackLink { app.go(.collect) }
                Spacer(minLength: 0)
                if let c = app.collecting {
                    Pill(text: Text(c.subjectId).font(.system(size: 15, weight: .semibold, design: .monospaced)) + Text(", session \(c.session)"))
                }
            }
            .frame(minHeight: 44)

            // The title
            H1(text: "About the participant", size: 40, lineHeight: 1.1, top: 20)

            // The form card, with a thin line between each part
            Card(padding: 0, spacing: 0) {

                // The consent box
                CheckRow(text: Copy.collectConsent, checked: m.consent, compact: true) { m.consent.toggle() }
                    .padding(.vertical, 22)
                    .padding(.horizontal, 28)
                Hairline()

                // The age box and the age group note
                FormRow(label: "Age") {
                    NumberField(text: Binding(get: { m.ageText }, set: { m.ageText = $0 }), decimal: false)
                    Text(m.bracket).text(.sub)
                }
                Hairline()

                // The drawing hand chips
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Drawing hand")
                    ChipGrid(items: [(value: "left", label: "Left"), (value: "right", label: "Right")], selected: m.hand) { value in m.hand = value }
                }
                .padding(.vertical, 22)
                .padding(.horizontal, 28)
                Hairline()

                // The diagnosis chips and a note under them
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

                // The box for hours after the last dose, only for Parkinson's
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

            // The Begin spirals button at the bottom
            Spacer(minLength: 0)
            VStack(spacing: 12) {

                // A line listing what is still needed, while anything is missing
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


// A row on the form with a label and its content
private struct FormRow<Content: View>: View {

    // The label and the content
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {

        // The label beside the content if they fit, and above it if not
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


// A box for typing a number
private struct NumberField: View {

    // The text in the box, and whether it takes a decimal point
    @Binding var text: String
    var decimal: Bool

    // The colors
    @Environment(\.palette) private var p

    var body: some View {

        // A number keyboard and large digits in a rounded box with a border
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


// The screen where the participant draws the spirals
struct CollectDrawScreen: View {

    // The app model and text sizes
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.collect
        CollectBody(centered: true) {

            // The back link, the spiral count, and the participant ID and session number
            Bar(side: 160) {
                BackLink { Task { await m.back() } }
            } center: {
                H1(text: m.count, size: 21, lineHeight: 1.3, top: 0, weight: 600)
            } right: {
                if let c = app.collecting {
                    (Text(c.subjectId).font(.system(size: 15, design: .monospaced)) + Text(", session \(c.session)")).text(.sub)
                }
            }

            // The progress bar, one segment per spiral
            Segments(total: CollectModel.collectTrials, done: m.progressDone, width: 180, height: 6, gap: 8)
                .id(m.trialID)
                .padding(.top, 8)

            // The instruction
            Text(Copy.collectDrawInstruction).text(.lede).frame(maxWidth: 620).padding(.top, 24)

            // The drawing pad, 280 to 680 points based on the screen's height
            PadBox(cap: max(min(680, typo.height - 420), 280)) {
                PadView(pad: m.pad)
            }
            .padding(.top, 28)

            // The status line
            StatusBox(sentence: m.status, shake: m.shaker.x).multilineTextAlignment(.leading)

            // The redo and next buttons at the bottom
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


// The screen shown once a session is saved
struct CollectDoneScreen: View {

    // The app model and colors
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        let m = app.collect
        CollectBody(padTop: 96, centered: true) {

            // A checkmark in a circle
            ZStack {
                Circle().fill(p.accentSoft.color)
                IconView(icon: .checkmark, size: 46, weight: 2.4).foregroundStyle(p.accent.color)
            }
            .frame(width: 96, height: 96)

            // The title and a short line
            H1(text: "Session saved", size: 44, lineHeight: 1.08, top: 28)
            Text(Copy.sessionSaved).text(.lede).frame(maxWidth: 560)

            // A card with the facts about the saved session
            if let s = app.collecting?.saved {

                // Each fact as a label and a value
                let facts: [(String, String)] = [
                    ("Participant", s.subjectId),
                    ("Session", String(s.session)),
                    ("Age", s.age.map { String($0) } ?? "Not given"),
                    ("Drawing hand", s.hand == "left" ? "Left" : "Right"),
                    ("Diagnosis", Copy.diagnoses[s.diagnosis] ?? s.diagnosis),
                    ("Input", ["pencil": "Apple Pencil", "touch": "Finger", "mouse": "Mouse"][s.inputType ?? ""] ?? s.inputType ?? "Not recorded"),
                ]

                // The facts in two columns, with a thin line above every row after the first
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

            // The export and next participant buttons at the bottom
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
