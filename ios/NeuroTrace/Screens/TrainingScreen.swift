// TRAININGSCREEN.SWIFT IS THE TRAINING TAB
// IT SHOWS TODAY'S FOCUS EXERCISE, A CARD FOR EVERY EXERCISE, AND THIS WEEK'S PRACTICE DAYS

import SwiftUI

// Writes a date as a short month and day
private let focusDayFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("MMMd")
    return format
}()

// Gives the sentence that says why today's focus is that exercise
func focusReason(_ focus: Practice.Focus) -> String {

    // Use a set sentence when there is no check in yet, or when no measure stood out
    guard let ts = focus.checkinTs else { return Copy.focusNoCheckin }
    guard let measure = focus.measure else { return Copy.focusNothingStoodOut }

    // Otherwise name the measure and the date of the check in
    return Copy.trainingWhy(measure, focusDayFmt.string(from: Date(timeIntervalSince1970: Double(ts) / 1000)))
}

// Holds what the training screen needs
@MainActor
@Observable
final class TrainingModel {

    // The main app model
    unowned let app: AppModel

    // The exercises in the order they show
    static let order = Practice.exercises

    // The level and note to show on each exercise's card
    var cards: [String: (level: String, note: String)] = [:]

    // Today's focus and this week's practice days, filled in once the tries and check ins are read
    var focus: Practice.Focus? = nil
    var week: [Bool?] = []

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // Fills in the cards, today's focus and the week when the screen shows
    func onShow() {

        // Build the level and note for each exercise
        for id in TrainingModel.order {

            // Exercises that aren't built yet say coming soon
            if !(Train.exercises[id]?.built ?? false) {
                cards[id] = (level: Copy.comingSoon, note: "")
                continue
            }

            // Show the level, and either not started, the last change, or the hits so far
            let state = Store.getTrainingState(id)
            let level = Copy.levelShort((state?.level ?? 0) + 1)
            let note = state == nil ? Copy.notStarted : state!.last.flatMap { last in Copy.lastChange[last] } ?? Copy.hitsSoFar(state!.hits, Train.hitsToLevelUp)
            cards[id] = (level: level, note: note)
        }

        // Read the tries and the latest check in, then work out today's focus and the week
        Task {
            let tries = (try? await Store.listTrainingTries()) ?? []
            let latest = (try? await Store.listAssessments())?.first
            focus = Practice.focus(latest: latest, lastPracticed: Practice.lastPracticed(tries))
            week = Practice.week(tries.map { t in t.ts }, now: Date())
        }
    }

    // Opens an exercise, or shows a toast if it isn't built yet
    func open(_ id: String) {
        if Train.exercises[id]?.built ?? false { app.go(.exercise, id) } else { Motion.toast(Copy.notBuilt, ok: false) }
    }
}


// The training screen itself
struct TrainingScreen: View {

    // The app model, colors and text sizes
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.training
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, tabbed: true, titled: true) { _ in

            // The title and a short description
            H1(text: "Training")
            Text(Copy.trainingBlurb).text(.lede).padding(.top, 10)

            // Today's focus card with the exercise, its level, the reason, and a Start button
            if let focus = m.focus {
                Text("Today\u{2019}s focus").text(.sectionTitle).padding(.top, 28)
                Card {
                    Text(Copy.exerciseNames[focus.exercise] ?? focus.exercise).text(.cardTitle)
                    Text(m.cards[focus.exercise]?.level ?? "").text(.sub)
                    Text(focusReason(focus)).text(.body).fixedSize(horizontal: false, vertical: true)
                    Btn(title: "Start") { m.open(focus.exercise) }.padding(.top, 4)
                }
                .padding(.top, 12)
            }

            // All the exercises, two cards in each row on every screen size
            Text("All exercises").text(.sectionTitle).padding(.top, 28)
            let perRow = 2
            let order = TrainingModel.order
            VStack(spacing: 12) {
                ForEach(Array(stride(from: 0, to: order.count, by: perRow)), id: \.self) { start in
                    let row = Array(order[start..<min(start + perRow, order.count)])
                    HStack(alignment: .top, spacing: 12) {

                        // Each card shows the name, level and note, and opens the exercise when tapped
                        ForEach(row, id: \.self) { id in
                            Button {
                                m.open(id)
                            } label: {
                                Card(spacing: 2, fill: true) {
                                    Text(Copy.exerciseNames[id] ?? id).text(.strong).padding(.bottom, 2)
                                    Text(m.cards[id]?.level ?? "").text(.sub)
                                    Text(m.cards[id]?.note ?? "").text(.sub)
                                }
                                .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(PressStyle(dim: false))
                        }

                        // Fill an empty spot in the last row with blank space
                        ForEach(row.count..<perRow, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 12)

            // This week's practice days, once they are read
            if !m.week.isEmpty {
                Text("This week").text(.sectionTitle).padding(.top, 28)
                Card {

                    // Show the dots, count and link in one row if they fit, or the dots above the other two if not
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 20) { weekDots(m.week); weekNum(m.week); Spacer(minLength: 0); weekLink }
                        VStack(alignment: .leading, spacing: 12) {
                            weekDots(m.week)
                            HStack(spacing: 20) { weekNum(m.week); Spacer(minLength: 0); weekLink }
                        }
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    // Shows one dot per day of the week with the day's letter under it
    // Days with practice are filled, other past days are gray, and days still to come are an outline
    private func weekDots(_ week: [Bool?]) -> some View {

        // The day letters, starting from the first day of the week on this device
        let calendar = Calendar.current
        let letters = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1

        // Count the days with practice and the days so far
        let practiced = week.filter { d in d == true }.count, soFar = week.filter { d in d != nil }.count
        return HStack(spacing: 10) {
            ForEach(0..<week.count, id: \.self) { i in
                VStack(spacing: 4) {
                    if let done = week[i] {
                        Circle().fill(done ? p.accent.color : p.fill.color).frame(width: 14, height: 14)
                    } else {
                        Circle().strokeBorder(p.fill.color, lineWidth: 2).frame(width: 14, height: 14)
                    }
                    Text(letters[(first + i) % letters.count]).nt(.body(12, 600, lineHeight: 1.2)).foregroundStyle(p.ink2.color)
                }
            }
        }
        // Screen readers read the dots as one sentence about the week
        .accessibilityElement()
        .accessibilityLabel(Copy.weekSpoken(practiced, soFar))
    }

    // Shows how many days had practice out of the days so far, hidden from screen readers
    private func weekNum(_ week: [Bool?]) -> some View {
        let practiced = week.filter { d in d == true }.count, soFar = week.filter { d in d != nil }.count
        return Text(Copy.weekCount(practiced, soFar)).text(.strong).monospacedDigit().accessibilityHidden(true)
    }

    // The See progress link that opens the progress screen
    private var weekLink: some View {
        Button {
            app.go(.progress)
        } label: {
            HStack(spacing: 2) {
                Text("See progress").nt(.body(17, 600, lineHeight: 1.5))
                IconView(icon: .chevron, size: 20, weight: 2.2)
            }
            .foregroundStyle(p.accent.color)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }
}
