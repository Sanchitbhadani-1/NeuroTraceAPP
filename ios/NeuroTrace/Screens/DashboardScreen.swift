// DASHBOARDSCREEN.SWIFT IS THE TODAY SCREEN
// IT SHOWS TODAY'S SPIRAL CHECK IN, TODAY'S EXERCISE AND THE DOSE CARD, AS SHORTCUTS INTO THE OTHER TABS

import SwiftUI
import UIKit

// Turns a time into hours and minutes
private let timeFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("jjmm")
    return format
}()

// Turns a time into the weekday, month and day
private let dayFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("EEEEMMMd")
    return format
}()

// Turns a time in milliseconds into "Today", "Yesterday" or the date, followed by the time
func historyWhen(_ ts: Int) -> String {
    let d = Date(timeIntervalSince1970: Double(ts) / 1000), today = Date()
    let time = timeFmt.string(from: d)

    // Count the days between that day and today
    let calendar = Calendar.current
    let days = Int(jsRound(calendar.startOfDay(for: today).timeIntervalSince(calendar.startOfDay(for: d)) / 86400))

    // Say Today or Yesterday when it fits, or the date otherwise
    if days == 0 { return "Today, \(time)" }
    if days == 1 { return "Yesterday, \(time)" }
    return "\(dayFmt.string(from: d)), \(time)"
}

// Turns today's date into the heading under Today, like Thursday, October 22
private let todayFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
    return format
}()


// THE DASHBOARD MODEL

// Holds what the Today screen needs
@MainActor
@Observable
final class DashboardModel {

    // The main app model, and every check in, newest first
    unowned let app: AppModel
    var records: [AssessmentRecord] = []

    // Today's suggested exercise and its level, and if any practice happened today
    var focus: Practice.Focus? = nil
    var focusLevel = ""
    var practicedToday = false

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // Load the check ins and today's exercise when the screen shows
    func onShow() {

        // Load the medicine and last dose for the dose card
        app.care.refresh()
        Task {

            // Load every check in, or use none and print an error if it fails
            do {
                records = try await Store.listAssessments()
            } catch {
                print("NeuroTrace: couldn't read history", error)
                records = []
            }

            // Load the practice tries and pick today's exercise and its level
            let tries = (try? await Store.listTrainingTries()) ?? []
            let next = Practice.focus(latest: records.first, lastPracticed: Practice.lastPracticed(tries))
            focusLevel = Copy.levelShort((Store.getTrainingState(next.exercise)?.level ?? 0) + 1)
            focus = next

            // Check if any practice happened today
            practicedToday = Practice.doneToday(tries.map { t in t.ts }, now: Date())
        }
    }

    // The newest check in, if it was done today
    var todayCheckin: AssessmentRecord? {
        records.first.flatMap { r in Practice.doneToday([r.ts], now: Date()) ? r : nil }
    }
}


// THE PARTS OF THE SCREEN

// A row in a list of check ins with the time, a line under it and an arrow, that runs an action when tapped
struct HistoryRow: View {

    // The time, the line under it, if the time uses a fixed width font, and what a tap does
    let when: String
    let sub: String
    var mono = false
    let action: () -> Void

    // The colors
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {

                // The time, in a fixed width font when mono is on, and the line under it
                VStack(alignment: .leading, spacing: 2) {
                    if mono {
                        Text(when).nt(.mono(21, 600, lineHeight: 1.3)).foregroundStyle(p.ink.color)
                    } else {
                        Text(when).text(.strong)
                    }
                    Text(sub).text(.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The arrow on the right
                IconView(icon: .chevron, size: 20, weight: 2.2).foregroundStyle(p.ink2.color)
            }
            // Padding on the sides only when mono is off
            .padding(.vertical, 12)
            .padding(.leading, mono ? 0 : 20)
            .padding(.trailing, mono ? 0 : 16)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }
}

// A button style that fills the row with gray while it is pressed
private struct RowPress: ButtonStyle {

    // The colors
    @Environment(\.palette) private var p

    // Fill the background while pressed, and clear it otherwise
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? p.fill.color : Color.clear)
    }
}

// A round checkmark for things already done today
private struct DoneCheckmark: View {

    // The colors
    @Environment(\.palette) private var p

    var body: some View {

        // A checkmark in a soft colored circle, hidden from screen readers
        IconView(icon: .checkmark, size: 20, weight: 2.6)
            .foregroundStyle(p.accent.color)
            .frame(width: 36, height: 36)
            .background(Circle().fill(p.accentSoft.color))
            .accessibilityHidden(true)
    }
}


// THE SCREEN

// The Today screen itself
struct DashboardScreen: View {

    // The app model, colors and text sizes shared by every screen
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.dashboard
        let wide = typo.width >= 900

        // Use a wider page on wide screens
        ScreenView(maxWidth: wide ? 1040 : 560, tabbed: true, titled: true) { _ in

            // Without tabs on top, show the mascot, the app name and the settings button here
            if !typo.tabsOnTop {
                HStack(spacing: 10) {
                    Mascot(mood: "idle").frame(width: 36, height: 36)
                    Text("NeuroTrace").text(.brand(21))
                    Spacer(minLength: 0)
                    settingsButton
                }
                .frame(minHeight: 44)
            }

            // The Today headline and today's date
            H1(text: "Today", top: typo.tabsOnTop ? 0 : 16)
            Text(todayFmt.string(from: Date())).text(.lede).padding(.top, 6)

            // On wide screens, show the check in on the left and the exercise and dose card on the right
            if wide {
                HStack(alignment: .top, spacing: 24) {
                    checkin(m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 16) {
                        exercise(m)
                        DoseCard(m: app.care, full: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 24)
            } else {

                // On narrow screens, show the cards in one column
                checkin(m).padding(.top, 24)
                exercise(m).padding(.top, 16)
                DoseCard(m: app.care, full: false).padding(.top, 16)
            }

            // The privacy note at the bottom
            Spacer(minLength: 0)
            LockNote().padding(.top, 24)
        }
    }

    // The gear button that opens settings
    private var settingsButton: some View {
        Button {
            app.go(.settings)
        } label: {
            IconView(icon: .settings, size: 24)
                .foregroundStyle(p.ink2.color)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.95, dim: false))
        .accessibilityLabel("Settings")
    }

    // Today's check in card, or what today's check in found once it's done
    @ViewBuilder
    private func checkin(_ m: DashboardModel) -> some View {

        // With a check in done today, show it as done with its result
        if let done = m.todayCheckin {
            Card(spacing: 12) {

                // The checkmark, the title and the time
                HStack(spacing: 12) {
                    DoneCheckmark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spiral check-in done").text(.cardTitle)
                        Text(historyWhen(done.ts)).text(.sub)
                    }
                }

                // The result level
                if let r = done.result { Text(Copy.tiers[r.tier].label).text(.strong) }

                // The buttons to see the result or check in again
                ButtonPair {
                    Btn(title: "See today's result", kind: .secondary) { app.go(.results, "\(done.id ?? 0)") }
                } second: {
                    Btn(title: "Check in again", kind: .secondary) { app.go(.about) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Spiral check-in")
        } else {

            // Without one, show the card to start a check in
            Card(spacing: 16) {

                // The title, a short description and the small spiral picture
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spiral check-in").text(.h1(24, 1.15, 500)).accessibilityAddTraits(.isHeader)
                        Text(Copy.checkinBlurb).text(.lede).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    MiniArt()
                }

                // The start button
                Btn(title: "Start a check-in") { app.go(.about) }

                // The newest check in from an earlier day, opening its result when tapped
                if let last = m.records.first {
                    Hairline()
                    LastCheckin(when: historyWhen(last.ts), result: last.result.map { r in Copy.tiers[r.tier].label } ?? "") {
                        app.go(.results, "\(last.id ?? 0)")
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Spiral check-in")
        }
    }

    // Today's exercise from Training, with a checkmark once there's been practice today
    @ViewBuilder
    private func exercise(_ m: DashboardModel) -> some View {
        if let focus = m.focus {
            Card {

                // The title, the exercise name and level, and the checkmark when practiced today
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's exercise").text(.cardTitle)
                        Text("\(Copy.exerciseNames[focus.exercise] ?? focus.exercise), \(m.focusLevel)").text(.sub)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if m.practicedToday { DoneCheckmark() }
                }

                // The done note when practiced today, or the reason for this exercise
                Text(m.practicedToday ? Copy.practicedToday : focusReason(focus)).text(.body).fixedSize(horizontal: false, vertical: true)

                // The button that opens the exercise
                Btn(title: m.practicedToday ? "Practice again" : "Start", kind: m.practicedToday ? .secondary : .primary) {
                    app.training.open(focus.exercise)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Today's exercise")
        }
    }
}

// The newest check in, as a row that opens its result
private struct LastCheckin: View {

    // The time, the result level, and what a tap does
    let when: String
    let result: String
    let action: () -> Void

    // The colors
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {

                // The Last check in label, the time and the result level when there is one
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last check-in").text(.sub)
                    Text(when).text(.strong)
                    if !result.isEmpty { Text(result).text(.sub) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The arrow on the right
                IconView(icon: .chevron, size: 20, weight: 2.2).foregroundStyle(p.ink2.color)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98, dim: true))
        // Screen readers read the row as one item
        .accessibilityElement(children: .combine)
    }
}

// A text box with a label above it
struct Field: View {

    // The label, the gray text shown when empty, and the text typed in
    let label: String
    let placeholder: String
    @Binding var text: String

    // True to let the box grow up to 4 lines
    var multiline = false

    // The colors
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // The label, hidden from screen readers
            Text(label).text(.strong).accessibilityHidden(true)

            // The text box with a rounded border, and autocorrect off
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(p.ink2.color), axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 4 : 1)
                .nt(.body())
                .foregroundStyle(p.ink.color)
                .autocorrectionDisabled()
                .accessibilityLabel(label)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(minHeight: 56)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.surface.color))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.guide.color, lineWidth: p.hair))
        }
    }
}
