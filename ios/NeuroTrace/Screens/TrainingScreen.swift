import SwiftUI

private let focusDayFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("MMMd")
    return format
}()

// Why today's focus is that exercise, in one sentence. The dashboard shows it too
func focusReason(_ focus: Practice.Focus) -> String {
    guard let ts = focus.checkinTs else { return Copy.focusNoCheckin }
    guard let measure = focus.measure else { return Copy.focusNothingStoodOut }
    return Copy.trainingWhy(measure, focusDayFmt.string(from: Date(timeIntervalSince1970: Double(ts) / 1000)))
}

@MainActor
@Observable
final class TrainingModel {
    unowned let app: AppModel
    static let order = Practice.exercises
    var cards: [String: (level: String, note: String)] = [:]
    // Today's focus and this week's practice days, once the tries and check-ins have been read
    var focus: Practice.Focus? = nil
    var week: [Bool?] = []

    init(app: AppModel) { self.app = app }

    func onShow() {
        for id in TrainingModel.order {
            if !(Train.exercises[id]?.built ?? false) {
                cards[id] = (level: Copy.comingSoon, note: "")
                continue
            }
            let state = Store.getTrainingState(id)
            let level = Copy.levelShort((state?.level ?? 0) + 1)
            let note = state == nil ? Copy.notStarted : state!.last.flatMap { last in Copy.lastChange[last] } ?? Copy.hitsSoFar(state!.hits, Train.hitsToLevelUp)
            cards[id] = (level: level, note: note)
        }
        Task {
            let tries = (try? await Store.listTrainingTries()) ?? []
            let latest = (try? await Store.listAssessments())?.first
            focus = Practice.focus(latest: latest, lastPracticed: Practice.lastPracticed(tries))
            week = Practice.week(tries.map { t in t.ts }, now: Date())
        }
    }

    func open(_ id: String) {
        if Train.exercises[id]?.built ?? false { app.go(.exercise, id) } else { Motion.toast(Copy.notBuilt, ok: false) }
    }
}

struct TrainingScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.training
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, tabbed: true, titled: true) { _ in
            H1(text: "Training")
            Text(Copy.trainingBlurb).text(.lede).padding(.top, 10)

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

            Text("All exercises").text(.sectionTitle).padding(.top, 28)
            // Two a row on every size, so each card's level and note have room
            let perRow = 2
            let order = TrainingModel.order
            VStack(spacing: 12) {
                ForEach(Array(stride(from: 0, to: order.count, by: perRow)), id: \.self) { start in
                    let row = Array(order[start..<min(start + perRow, order.count)])
                    HStack(alignment: .top, spacing: 12) {
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
                        ForEach(row.count..<perRow, id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 12)

            if !m.week.isEmpty {
                Text("This week").text(.sectionTitle).padding(.top, 28)
                Card {
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

    // One dot per day of the week, filled on days with practice. Days still to come are an outline
    private func weekDots(_ week: [Bool?]) -> some View {
        let calendar = Calendar.current
        let letters = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
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
        .accessibilityElement()
        .accessibilityLabel(Copy.weekSpoken(practiced, soFar))
    }

    private func weekNum(_ week: [Bool?]) -> some View {
        let practiced = week.filter { d in d == true }.count, soFar = week.filter { d in d != nil }.count
        return Text(Copy.weekCount(practiced, soFar)).text(.strong).monospacedDigit().accessibilityHidden(true)
    }

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
