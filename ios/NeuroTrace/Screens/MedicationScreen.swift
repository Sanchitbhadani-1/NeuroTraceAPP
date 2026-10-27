// MEDICATIONSCREEN.SWIFT IS THE SCREEN FOR YOUR MEDICATION AND DOSES
// IT SAVES YOUR MEDICATION, LOGS AND LISTS DOSES, AND CHARTS YOUR DRAWING IN THE HOURS AFTER A DOSE

import SwiftUI

// How many doses the list shows
private let dosesShown = 10


// THE MEDICATION MODEL

// Holds what the medication screen needs, and saves the medication and doses
@MainActor
@Observable
final class MedicationModel {

    // The main app model
    unowned let app: AppModel

    // True once the doses and check ins have loaded
    var loaded = false

    // The medicine's name and schedule typed on screen
    var name = ""
    var schedule = ""

    // The time for the next dose logged on this screen
    var when = Date()

    // The saved doses, and the measure picked for the chart
    var doses: [Dose] = []
    var measure = Meds.timingMeasures[0]

    // The hand and pen or finger used for most check ins, and the chart uses only those check ins
    var setup: (hand: String, inputType: String?)? = nil

    // True while a dose is being saved, and other taps on Log do nothing
    var saving = false

    // True while removing a dose, and other taps on Remove do nothing
    @ObservationIgnored private var removing = false

    // The check ins grouped by time after a dose, and every scored check in
    var timing: Meds.Timing? = nil
    @ObservationIgnored private var checkins: [Meds.Checkin] = []

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // Load the saved medication, reset the dose time, and load the doses when the screen shows
    func onShow() {
        let saved = Store.getMedication()
        name = saved.name
        schedule = saved.schedule
        when = Date()
        loaded = false
        Task { await reload() }
    }

    // Read the doses and check ins again, then redo the chart
    func reload() async {

        // Load the doses and the check ins
        doses = (try? await Store.listDoses()) ?? []
        let records = (try? await Store.listAssessments()) ?? []

        // With a check in and the scoring files, find the main setup and score every check in
        if let latest = records.first, let scoring = try? await app.scoring.value {
            setup = Meds.mainSetup(records)

            // Score every check in against the newest one's age group
            checkins = Meds.checkins(records) { rec in
                Score.scoreSession([rec.features ?? rec.result?.features ?? [:]], scoring.model, scoring.reference, latest.bracketChoice).measurePct
            }
        } else {

            // Otherwise clear the setup and the check ins
            setup = nil
            checkins = []
        }

        // Redo the chart and mark the screen as loaded
        recount()
        loaded = true
    }

    // Group the check ins by time after a dose, for the picked measure
    func recount() {
        if let setup {
            timing = Meds.doseTiming(checkins: checkins, doses: doses, measure: measure, hand: setup.hand, inputType: setup.inputType)
        } else {
            timing = nil
        }
    }

    // Pick a measure for the chart and redo it
    func pick(_ key: String) {
        measure = key
        recount()
    }

    // Save the medicine's name and schedule with spaces trimmed off the ends
    func saveMedication() {
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        Store.setMedication(Store.Medication(name: trim(name), schedule: trim(schedule)))
        Motion.toast(Copy.saved)
    }

    // Save a dose at the time picked on screen
    func logDose() {
        if saving { return }

        // Use the picked time, or now if the picked time is later
        let ts = Int(min(when, Date()).timeIntervalSince1970 * 1000)

        // Show a message and stop if a dose is already logged within a minute of it
        if doses.contains(where: { d in abs(d.ts - ts) < 60_000 }) { return Motion.toast(Copy.doseTwice, ok: false) }

        // Mark saving until this ends
        saving = true
        Task {
            defer { saving = false }

            // Save the dose, show a message, reset the time and reload
            do {
                _ = try await Store.saveDose(Dose(ts: ts))
                Motion.toast(Copy.doseLogged)
                when = Date()
                await reload()
            } catch {

                // If it fails, print the error and show a message
                print("NeuroTrace: couldn't save the dose", error)
                Motion.toast(Copy.doseNotSaved, ok: false)
            }
        }
    }

    // Ask first, then remove a saved dose
    func remove(_ dose: Dose) {

        // Stop if the dose has no id or another remove is open, and mark removing until this ends
        guard let id = dose.id, !removing else { return }
        removing = true
        Task {
            defer { removing = false }

            // Stop if they don't confirm
            if !(await confirm(Copy.removeDoseConfirm, action: "Remove")) { return }

            // Delete the dose and reload
            do {
                try await Store.deleteDose(id)
                await reload()
            } catch {

                // If it fails, print the error and show a message
                print("NeuroTrace: couldn't remove the dose", error)
                Motion.toast(Copy.doseNotRemoved, ok: false)
            }
        }
    }
}


// THE SCREEN

// The medication screen itself
struct MedicationScreen: View {

    // The app model, colors and text sizes shared by every screen
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.medication

        // The tab this was opened from, or the dashboard
        let back = app.cameFrom.flatMap { from in AppModel.tabs.contains(from) ? from : nil } ?? .dashboard

        // Use a wider page on wide screens
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, titled: true) { _ in

            // The back link, the headline and a short description
            BackLink(label: TabBar.items.first { item in item.id == back }?.label ?? "Back") { app.go(back) }
            H1(text: "Medication")
            Text(Copy.medLede).text(.lede).padding(.top, 10)

            // The medicine's name and schedule
            Card {
                Text("Your medication").text(.cardTitle)
                Text(Copy.medBlurb).text(.sub)
                Field(label: "Medication", placeholder: "Name", text: Binding(get: { m.name }, set: { v in m.name = v }))
                Field(label: "Dose and times", placeholder: "Like 1 tablet at 8 AM and 2 PM", text: Binding(get: { m.schedule }, set: { v in m.schedule = v }), multiline: true)
                Btn(title: "Save medication", kind: .secondary) { m.saveMedication() }
            }
            .padding(.top, 24)

            // The card to log a dose at a picked time
            Card {
                Text("Log a dose").text(.cardTitle)
                Text(Copy.logDoseHelp).text(.sub)

                // The Taken label and the time picker side by side when they fit, or stacked when they don't
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        Text("Taken").text(.strong).accessibilityHidden(true)
                        Spacer(minLength: 0)
                        takenPicker(m)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Taken").text(.strong).accessibilityHidden(true)
                        takenPicker(m)
                    }
                }

                // The Log button, turned off while saving
                Btn(title: "Log this dose", disabled: m.saving) { m.logDose() }
            }
            .padding(.top, 16)

            // The list of doses
            Text("Your doses").text(.sectionTitle).padding(.top, 28)

            // With no doses, show a note
            if m.doses.isEmpty {
                Card(alignment: .center) {
                    Text(Copy.noDoses).text(.lede).multilineTextAlignment(.center)
                }
                .padding(.top, 12)
            } else {

                // Otherwise show the newest doses, one row each, with a thin line between rows
                let shown = Array(m.doses.prefix(dosesShown))
                Card(padding: 0, spacing: 0) {
                    ForEach(0..<shown.count, id: \.self) { i in
                        if i > 0 { Hairline() }
                        doseRow(shown[i], m)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 12)

                // With more doses than shown, say only the recent ones are shown
                if m.doses.count > dosesShown {
                    Text(Copy.recentDoses(dosesShown)).text(.sub).padding(.top, 8)
                }
            }

            // The chart of the best time after a dose, once loaded
            if m.loaded {
                timing(m).padding(.top, 28)
            }

            // The Done button at the bottom
            Spacer(minLength: 0)
            Btn(title: "Done", kind: .secondary) { app.go(back) }
                .padding(.top, 28)
        }
    }

    // The date and time picker for when the dose was taken, up to now
    private func takenPicker(_ m: MedicationModel) -> some View {
        DatePicker("Taken", selection: Binding(get: { m.when }, set: { v in m.when = v }), in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
            .datePickerStyle(.compact)
            .accessibilityLabel("Taken")
    }

    // One dose with its time and a Remove button
    private func doseRow(_ dose: Dose, _ m: MedicationModel) -> some View {
        HStack(spacing: 12) {

            // The time of the dose
            Text(historyWhen(dose.ts)).text(.strong).frame(maxWidth: .infinity, alignment: .leading)

            // The Remove button
            Button {
                m.remove(dose)
            } label: {
                Text("Remove")
                    .nt(.body(15, 600, lineHeight: 1.2))
                    .foregroundStyle(p.accent.color)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove the dose from \(historyWhen(dose.ts))")
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(minHeight: 60)
    }

    // The chart of how drawing changes in the hours after a dose, once there are enough check ins
    @ViewBuilder
    private func timing(_ m: MedicationModel) -> some View {
        ResultCard(title: "Your best time after a dose") {
            Text(Copy.timingCaption).text(.sub)

            // A chip for each measure the chart can show
            ChipGrid(items: Meds.timingMeasures.map { k in (value: k, label: Copy.timingLabels[k] ?? k) }, selected: m.measure) { value in m.pick(value) }

            // What the check ins in the chart were drawn with
            if let setup = m.setup {
                Text(Copy.timingSetup(setup.hand, setup.inputType)).text(.sub)
            }

            // How many check ins were counted
            let counted = m.timing?.counted ?? 0

            // When the chart is ready, show the best time, its details and a row for each time window
            if let t = m.timing, t.ready, let best = t.best {
                Text(Copy.bestTime(best.from, best.to)).text(.h3).padding(.top, 8)
                Text(Copy.bestDetail(m.measure, best.median ?? 0, best.n)).text(.sub)
                ForEach(0..<t.bins.count, id: \.self) { i in
                    BinRow(bin: t.bins[i], best: t.bins[i] == best, index: i)
                }
            } else if counted < Meds.minCheckins {

                // With too few check ins, show how many so far and how to get more
                Text(Copy.timingSoFar(counted)).text(.strong).padding(.top, 8).accessibilityHidden(true)
                CountBar(done: counted, total: Meds.minCheckins)
                Text(Copy.timingHowTo).text(.sub)
            } else {

                // With enough check ins but no time window with two of them, show a note
                Text(Copy.timingSpread).text(.body).padding(.top, 8)
            }

            // The caution note at the bottom
            Text(Copy.timingCaution).text(.sub).padding(.top, 8)
        }
    }
}


// THE PARTS OF THE CHART

// One time window after a dose, with a bar for how its check ins compared with the reference group
private struct BinRow: View {

    // The time window, true if it is the best one, and its place in the reveal order
    let bin: Meds.Bin
    let best: Bool
    let index: Int

    // The colors, and if the bar has grown in
    @Environment(\.palette) private var p
    @State private var grown = false

    var body: some View {

        // The hours label, and the sentence screen readers read for the row
        let label = Copy.hoursAfter(bin.from, bin.to)
        let spoken = "\(label) after a dose, \(Copy.checkinCount(bin.n))" + (bin.median.map { v in ", \(Copy.betterThan(v))" } ?? "") + (best ? ", your best time" : "")
        return VStack(alignment: .leading, spacing: 4) {

            // The hours, in bold for the best one, and the number of check ins
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).text(best ? .strong : .body)
                Spacer(minLength: 0)
                Text(Copy.checkinCount(bin.n)).text(.sub)
            }

            // A gray track with the bar growing across it when there is a middle value
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(p.fill.color).frame(width: w, height: 6)
                    if let median = bin.median {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(best ? p.accent.color : p.ink2.color)
                            .frame(width: grown ? max(w * CGFloat(min(max(median, 0), 1)), 3) : 0, height: 6)
                            .animation(Motion.reduced() ? nil : .easeOut(duration: 0.55), value: grown)
                    }
                }
            }
            .frame(height: 6)
        }
        .fullWidth()
        .padding(.top, 12)
        // Screen readers read the row as one sentence
        .accessibilityElement()
        .accessibilityLabel(spoken)
        // Grow the bar on reveal
        .reveal(index) { grown = true }
    }
}

// A bar for how many of the needed check ins there are so far
private struct CountBar: View {

    // How many there are, how many are needed, and the colors
    let done: Int
    let total: Int
    @Environment(\.palette) private var p

    var body: some View {

        // A gray track with the filled part on top
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.fill.color)
                Capsule().fill(p.accent.color).frame(width: geo.size.width * CGFloat(min(done, total)) / CGFloat(max(total, 1)))
            }
        }
        .frame(height: 6)
        // Screen readers read how many so far
        .accessibilityElement()
        .accessibilityLabel(Copy.timingSoFar(done))
    }
}
