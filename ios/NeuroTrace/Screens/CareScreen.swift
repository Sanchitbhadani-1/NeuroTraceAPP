import SwiftUI
import UIKit

@MainActor
@Observable
final class CareModel {
    unowned let app: AppModel
    var medication = Store.Medication()
    var lastDose: Dose? = nil
    // True while a dose is being saved, so a quick second tap doesn't log it twice
    var savingDose = false

    init(app: AppModel) { self.app = app }

    func onShow() {
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

    var body: some View {
        let m = app.care
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, tabbed: true, titled: true) { _ in
            H1(text: "Care")
            Text(Copy.careBlurb).text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            DoseCard(m: m).padding(.top, 24)
        }
    }
}
