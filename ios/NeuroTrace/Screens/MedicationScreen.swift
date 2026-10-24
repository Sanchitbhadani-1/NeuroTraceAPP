import SwiftUI

// How many doses the list shows
private let dosesShown = 10

@MainActor
@Observable
final class MedicationModel {
    unowned let app: AppModel
    var loaded = false
    var name = ""
    var schedule = ""
    // The time for the next dose logged on this screen
    var when = Date()
    var doses: [Dose] = []
    var measure = Meds.timingMeasures[0]
    // The hand and pen or finger used for most check-ins. The chart only uses check-ins drawn that way
    var setup: (hand: String, inputType: String?)? = nil
    // True while a dose is being saved, so a quick second tap doesn't log it twice
    var saving = false
    // True while removing a dose, so a second tap doesn't ask twice
    @ObservationIgnored private var removing = false
    var timing: Meds.Timing? = nil
    @ObservationIgnored private var checkins: [Meds.Checkin] = []

    init(app: AppModel) { self.app = app }

    func onShow() {
        let saved = Store.getMedication()
        name = saved.name
        schedule = saved.schedule
        when = Date()
        loaded = false
        Task { await reload() }
    }

    // Read the doses and check-ins again, then redo the chart
    func reload() async {
        doses = (try? await Store.listDoses()) ?? []
        let records = (try? await Store.listAssessments()) ?? []
        if let latest = records.first, let scoring = try? await app.scoring.value {
            setup = Meds.mainSetup(records)
            // Every check-in placed against the newest one's reference group, the same as on Progress
            checkins = Meds.checkins(records) { rec in
                Score.scoreSession([rec.features ?? rec.result?.features ?? [:]], scoring.model, scoring.reference, latest.bracketChoice).measurePct
            }
        } else {
            setup = nil
            checkins = []
        }
        recount()
        loaded = true
    }

    // Group the check-ins by time after a dose, for the picked measure
    func recount() {
        if let setup {
            timing = Meds.doseTiming(checkins: checkins, doses: doses, measure: measure, hand: setup.hand, inputType: setup.inputType)
        } else {
            timing = nil
        }
    }

    func pick(_ key: String) {
        measure = key
        recount()
    }

    func saveMedication() {
        let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
        Store.setMedication(Store.Medication(name: trim(name), schedule: trim(schedule)))
        Motion.toast(Copy.saved)
    }

    // Save a dose at the time picked on screen. One within a minute of another isn't logged twice
    func logDose() {
        if saving { return }
        let ts = Int(min(when, Date()).timeIntervalSince1970 * 1000)
        if doses.contains(where: { d in abs(d.ts - ts) < 60_000 }) { return Motion.toast(Copy.doseTwice, ok: false) }
        saving = true
        Task {
            defer { saving = false }
            do {
                _ = try await Store.saveDose(Dose(ts: ts))
                Motion.toast(Copy.doseLogged)
                when = Date()
                await reload()
            } catch {
                print("NeuroTrace: couldn't save the dose", error)
                Motion.toast(Copy.doseNotSaved, ok: false)
            }
        }
    }

    func remove(_ dose: Dose) {
        guard let id = dose.id, !removing else { return }
        removing = true
        Task {
            defer { removing = false }
            if !(await confirm(Copy.removeDoseConfirm, action: "Remove")) { return }
            do {
                try await Store.deleteDose(id)
                await reload()
            } catch {
                print("NeuroTrace: couldn't remove the dose", error)
                Motion.toast(Copy.doseNotRemoved, ok: false)
            }
        }
    }
}

struct MedicationScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.medication
        // Back to the tab this was opened from, or the dashboard
        let back = app.cameFrom.flatMap { from in AppModel.tabs.contains(from) ? from : nil } ?? .dashboard
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, titled: true) { _ in
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

            // A dose taken earlier that wasn't logged at the time
            Card {
                Text("Log a dose").text(.cardTitle)
                Text(Copy.logDoseHelp).text(.sub)
                // Side by side when there's room, stacked on a narrow screen or with large text
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
                Btn(title: "Log this dose", disabled: m.saving) { m.logDose() }
            }
            .padding(.top, 16)

            Text("Your doses").text(.sectionTitle).padding(.top, 28)
            if m.doses.isEmpty {
                Card(alignment: .center) {
                    Text(Copy.noDoses).text(.lede).multilineTextAlignment(.center)
                }
                .padding(.top, 12)
            } else {
                let shown = Array(m.doses.prefix(dosesShown))
                Card(padding: 0, spacing: 0) {
                    ForEach(0..<shown.count, id: \.self) { i in
                        if i > 0 { Hairline() }
                        doseRow(shown[i], m)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 12)
                if m.doses.count > dosesShown {
                    Text(Copy.recentDoses(dosesShown)).text(.sub).padding(.top, 8)
                }
            }

            if m.loaded {
                timing(m).padding(.top, 28)
            }

            Spacer(minLength: 0)
            Btn(title: "Done", kind: .secondary) { app.go(back) }
                .padding(.top, 28)
        }
    }

    private func takenPicker(_ m: MedicationModel) -> some View {
        DatePicker("Taken", selection: Binding(get: { m.when }, set: { v in m.when = v }), in: ...Date(), displayedComponents: [.date, .hourAndMinute])
            .labelsHidden()
            .datePickerStyle(.compact)
            .accessibilityLabel("Taken")
    }

    private func doseRow(_ dose: Dose, _ m: MedicationModel) -> some View {
        HStack(spacing: 12) {
            Text(historyWhen(dose.ts)).text(.strong).frame(maxWidth: .infinity, alignment: .leading)
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

    // The chart of how drawing changes in the hours after a dose, once there are enough check-ins
    @ViewBuilder
    private func timing(_ m: MedicationModel) -> some View {
        ResultCard(title: "Your best time after a dose") {
            Text(Copy.timingCaption).text(.sub)
            // Chips rather than one segmented row, so the four names never squeeze or cut off
            ChipGrid(items: Meds.timingMeasures.map { k in (value: k, label: Copy.timingLabels[k] ?? k) }, selected: m.measure) { value in m.pick(value) }
            if let setup = m.setup {
                Text(Copy.timingSetup(setup.hand, setup.inputType)).text(.sub)
            }
            let counted = m.timing?.counted ?? 0
            if let t = m.timing, t.ready, let best = t.best {
                Text(Copy.bestTime(best.from, best.to)).text(.h3).padding(.top, 8)
                Text(Copy.bestDetail(m.measure, best.median ?? 0, best.n)).text(.sub)
                ForEach(0..<t.bins.count, id: \.self) { i in
                    BinRow(bin: t.bins[i], best: t.bins[i] == best, index: i)
                }
            } else if counted < Meds.minCheckins {
                Text(Copy.timingSoFar(counted)).text(.strong).padding(.top, 8).accessibilityHidden(true)
                CountBar(done: counted, total: Meds.minCheckins)
                Text(Copy.timingHowTo).text(.sub)
            } else {
                // Enough check-ins, but no time window has two of them yet
                Text(Copy.timingSpread).text(.body).padding(.top, 8)
            }
            Text(Copy.timingCaution).text(.sub).padding(.top, 8)
        }
    }
}

// One time window after a dose. The bar is how the check-ins in it compared with the reference group
private struct BinRow: View {
    let bin: Meds.Bin
    let best: Bool
    let index: Int
    @Environment(\.palette) private var p
    @State private var grown = false

    var body: some View {
        let label = Copy.hoursAfter(bin.from, bin.to)
        let spoken = "\(label) after a dose, \(Copy.checkinCount(bin.n))" + (bin.median.map { v in ", \(Copy.betterThan(v))" } ?? "") + (best ? ", your best time" : "")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).text(best ? .strong : .body)
                Spacer(minLength: 0)
                Text(Copy.checkinCount(bin.n)).text(.sub)
            }
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
        .accessibilityElement()
        .accessibilityLabel(spoken)
        .reveal(index) { grown = true }
    }
}

// How many of the needed check-ins there are so far
private struct CountBar: View {
    let done: Int
    let total: Int
    @Environment(\.palette) private var p

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(p.fill.color)
                Capsule().fill(p.accent.color).frame(width: geo.size.width * CGFloat(min(done, total)) / CGFloat(max(total, 1)))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel(Copy.timingSoFar(done))
    }
}
