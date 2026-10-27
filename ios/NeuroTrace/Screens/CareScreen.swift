// CARESCREEN.SWIFT IS THE CARE TAB
// IT SHOWS THE MEDICATION CARD, THE DOCTOR SUMMARY PDF, AND THE HOME SAFETY SCAN CARD

import SwiftUI
import UIKit

// Holds what the care screen needs, for medication, the doctor summary and the home scan
@MainActor
@Observable
final class CareModel {

    // The main app model
    unowned let app: AppModel

    // The saved medicine and the last dose taken
    var medication = Store.Medication()
    var lastDose: Dose? = nil

    // True while the doctor summary is being made
    var makingSummary = false

    // The note shown in the doctor card when there is nothing to put in a summary yet
    var summaryNote: String? = nil

    // True while a dose is being saved
    var savingDose = false

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // Clears the summary note and reads the saved medicine again when the screen shows
    func onShow() {
        summaryNote = nil
        refresh()
    }

    // Reads the saved medicine and the last dose again
    func refresh() {
        medication = Store.getMedication()
        Task { lastDose = try? await Store.listDoses().first }
    }

    // Saves a dose taken right now
    func logDoseNow() {

        // Do nothing while a dose is saving, and show a toast if the last dose was less than a minute ago
        if savingDose { return }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        if let last = lastDose, abs(now - last.ts) < 60_000 { return Motion.toast(Copy.doseTwice, ok: false) }

        // Save the dose, read the last dose again, and show a toast that says if it worked
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

    // Builds the doctor summary from everything saved on this device, then opens the share sheet with the PDF
    func shareSummary() async {

        // Do nothing if a summary is already being made
        if makingSummary { return }
        makingSummary = true
        defer { makingSummary = false }

        // Read the check ins and tapping tests
        let records = (try? await Store.listAssessments()) ?? []
        let taps = Store.getTapTests()

        // With no check ins and no counted tapping tests, show a note and read it out instead
        if records.isEmpty && !taps.contains(where: { t in t.result.counted }) {
            summaryNote = Copy.summaryEmpty
            UIAccessibility.post(notification: .announcement, argument: Copy.summaryEmpty)
            return
        }
        summaryNote = nil

        // Gather the scoring files, training levels, doses, medicine and tries
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

        // Make the PDF with today's date in its name and share it, showing a toast once it is shared
        let file = ExportFile(name: "NeuroTrace summary \(DoctorSummary.fileDate(Date())).pdf", data: SummaryPDF.render(DoctorSummary.build(input)))
        if await shareFile(file) { Motion.toast(Copy.summaryShared) }
    }
}


// The medication card with the dose button and the last dose
// The full card on Care also shows the medicine and links to the doses page
struct DoseCard: View {

    // The care model, whether to show the full card, and the app model
    let m: CareModel
    var full = true
    @Environment(AppModel.self) private var app

    var body: some View {
        Card {
            Text(full ? "Your medication" : "Medication").text(.cardTitle)

            // With no medicine saved, the full card says what the card is for
            if m.medication.name.isEmpty {
                if full { Text(Copy.medCardBlurb).text(.sub).fixedSize(horizontal: false, vertical: true) }
            } else {

                // Otherwise show the medicine name, and its schedule on the full card
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.medication.name).text(.strong)
                    if full && !m.medication.schedule.isEmpty { Text(m.medication.schedule).text(.sub) }
                }
            }

            // When the last dose was taken, or a note that there are no doses yet
            Text(m.lastDose.map { d in "Last dose: \(historyWhen(d.ts))" } ?? Copy.noDoses).text(.sub)

            // The full card has the dose button and a link to the doses page
            if full {
                ButtonPair {
                    Btn(title: "I just took a dose", kind: .secondary, disabled: m.savingDose) { m.logDoseNow() }
                } second: {
                    Btn(title: "Doses and timing", kind: .secondary) { app.go(.medication) }
                }
            } else {

                // The small card has only the dose button
                Btn(title: "I just took a dose", kind: .secondary, disabled: m.savingDose) { m.logDoseNow() }
            }
        }
        // Screen readers treat the card as one group with its title as the label
        .accessibilityElement(children: .contain)
        .accessibilityLabel(full ? "Your medication" : "Medication")
    }
}


// The care screen itself
struct CareScreen: View {

    // The app model, colors and text sizes
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    // True while the home scan is open
    @State private var scanning = false

    var body: some View {
        let m = app.care
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, tabbed: true, titled: true) { _ in

            // The title and a short description
            H1(text: "Care")
            Text(Copy.careBlurb).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 10)

            // The medication, doctor summary and home scan cards
            DoseCard(m: m).padding(.top, 24)
            doctor(m).padding(.top, 16)
            scan.padding(.top, 16)
        }
        // Open the home scan full screen, passing in the app model, colors and text sizes
        .fullScreenCover(isPresented: $scanning) {
            HomeScanScreen { present { scanning = false } }
                .environment(app)
                .environment(\.palette, p)
                .environment(\.typo, typo)
        }
    }

    // The card for making the doctor summary PDF
    private func doctor(_ m: CareModel) -> some View {
        Card(spacing: 12) {
            Text("For your doctor").text(.cardTitle)
            Text(Copy.summaryBlurb).text(.sub).fixedSize(horizontal: false, vertical: true)

            // The button, which is off and says it is working while the summary is made
            Btn(title: m.makingSummary ? "Making the summary\u{2026}" : "Make a summary PDF", kind: .secondary, icon: .export, disabled: m.makingSummary) {
                Task { await m.shareSummary() }
            }

            // The note when there is nothing to summarize yet
            if let note = m.summaryNote { Text(note).text(.sub).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("For your doctor")
    }

    // The card that opens the home safety scan
    private var scan: some View {
        Card(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Home safety scan").text(.cardTitle)
                Text(Copy.scanBlurb).text(.sub).fixedSize(horizontal: false, vertical: true)
            }
            Btn(title: "Scan a room") { present { scanning = true } }
        }
    }

    // Opens or closes the home scan, with no slide when Reduced Motion is on
    private func present(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = Motion.reduced()
        withTransaction(transaction, change)
    }
}
