import SwiftUI
import UIKit

// Looking after yourself outside the tests and exercises. Medication, a summary for the doctor and the home scan
@MainActor
@Observable
final class CareModel {
    unowned let app: AppModel
    var medication = Store.Medication()
    var lastDose: Dose? = nil
    // True while the doctor summary is being made, so a second tap doesn't start another
    var makingSummary = false
    // Shown in the doctor card when there's nothing to put in a summary yet
    var summaryNote: String? = nil
    // True while a dose is being saved, so a quick second tap doesn't log it twice
    var savingDose = false

    init(app: AppModel) { self.app = app }

    func onShow() {
        summaryNote = nil
        refresh()
    }

    // Reads the saved medicine and the last dose again. The dashboard uses these for its dose button too
    func refresh() {
        medication = Store.getMedication()
        Task { lastDose = try? await Store.listDoses().first }
    }

    // Save a dose taken right now. A second tap within a minute doesn't log it twice
    func logDoseNow() {
        if savingDose { return }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        if let last = lastDose, abs(now - last.ts) < 60_000 { return Motion.toast(Copy.doseTwice, ok: false) }
        savingDose = true
        Task {
            defer { savingDose = false }
            do {
                _ = try await Store.saveDose(Dose(ts: now))
                lastDose = try await Store.listDoses().first
                Motion.toast(Copy.doseLogged)
            } catch {
                print("NeuroTrace: couldn't save the dose", error)
                Motion.toast(Copy.doseNotSaved, ok: false)
            }
        }
    }

    // Build the doctor summary from everything saved on this device, then open the share sheet with the PDF
    func shareSummary() async {
        if makingSummary { return }
        makingSummary = true
        defer { makingSummary = false }
        let records = (try? await Store.listAssessments()) ?? []
        let taps = Store.getTapTests()
        if records.isEmpty && !taps.contains(where: { t in t.result.counted }) {
            summaryNote = Copy.summaryEmpty
            UIAccessibility.post(notification: .announcement, argument: Copy.summaryEmpty)
            return
        }
        summaryNote = nil
        let scoring = try? await app.scoring.value
        var levels: [String: Train.LevelState] = [:]
        for id in Practice.exercises { levels[id] = Store.getTrainingState(id) }
        let input = DoctorSummary.Input(
            records: records,
            model: scoring?.model,
            reference: scoring?.reference,
            tapTests: taps,
            doses: (try? await Store.listDoses()) ?? [],
            medication: Store.getMedication(),
            tries: (try? await Store.listTrainingTries()) ?? [],
            levels: levels,
            now: Date()
        )
        let file = ExportFile(name: "NeuroTrace summary \(DoctorSummary.fileDate(Date())).pdf", data: SummaryPDF.render(DoctorSummary.build(input)))
        if await shareFile(file) { Motion.toast(Copy.summaryShared) }
    }
}

// The dose button and the last dose. On Care it also shows the medicine and links to the doses page
struct DoseCard: View {
    let m: CareModel
    var full = true
    @Environment(AppModel.self) private var app

    var body: some View {
        Card {
            Text(full ? "Your medication" : "Medication").text(.cardTitle)
            // The saved name and schedule, or what the card is for if nothing is saved yet
            if m.medication.name.isEmpty {
                if full { Text(Copy.medCardBlurb).text(.sub).fixedSize(horizontal: false, vertical: true) }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.medication.name).text(.strong)
                    if full && !m.medication.schedule.isEmpty { Text(m.medication.schedule).text(.sub) }
                }
            }
            Text(m.lastDose.map { d in "Last dose: \(historyWhen(d.ts))" } ?? Copy.noDoses).text(.sub)
            if full {
                ButtonPair {
                    Btn(title: "I just took a dose", kind: .secondary, disabled: m.savingDose) { m.logDoseNow() }
                } second: {
                    Btn(title: "Doses and timing", kind: .secondary) { app.go(.medication) }
                }
            } else {
                Btn(title: "I just took a dose", kind: .secondary, disabled: m.savingDose) { m.logDoseNow() }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(full ? "Your medication" : "Medication")
    }
}

struct CareScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo
    @State private var scanning = false

    var body: some View {
        let m = app.care
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, tabbed: true, titled: true) { _ in
            H1(text: "Care")
            Text(Copy.careBlurb).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            DoseCard(m: m).padding(.top, 24)
            doctor(m).padding(.top, 16)
            scan.padding(.top, 16)
        }
        .fullScreenCover(isPresented: $scanning) {
            HomeScanScreen { present { scanning = false } }
                .environment(app)
                .environment(\.palette, p)
                .environment(\.typo, typo)
        }
    }

    // The doctor summary PDF
    private func doctor(_ m: CareModel) -> some View {
        Card(spacing: 12) {
            Text("For your doctor").text(.cardTitle)
            Text(Copy.summaryBlurb).text(.sub).fixedSize(horizontal: false, vertical: true)
            Btn(title: m.makingSummary ? "Making the summary\u{2026}" : "Make a summary PDF", kind: .secondary, icon: .export, disabled: m.makingSummary) {
                Task { await m.shareSummary() }
            }
            if let note = m.summaryNote { Text(note).text(.sub).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("For your doctor")
    }

    private var scan: some View {
        Card(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home safety scan").text(.cardTitle)
                Text(Copy.scanBlurb).text(.sub).fixedSize(horizontal: false, vertical: true)
            }
            Btn(title: "Scan a room") { present { scanning = true } }
        }
    }

    // Opens or closes the home scan, with no slide when Motion is set to Reduced
    private func present(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = Motion.reduced()
        withTransaction(transaction, change)
    }
}
