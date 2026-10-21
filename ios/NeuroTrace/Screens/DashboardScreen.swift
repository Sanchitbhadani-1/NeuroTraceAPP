import SwiftUI
import UIKit

private let timeFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("jjmm")
    return format
}()

private let dayFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("EEEEMMMd")
    return format
}()

func historyWhen(_ ts: Int) -> String {
    let d = Date(timeIntervalSince1970: Double(ts) / 1000), today = Date()
    let time = timeFmt.string(from: d)
    let calendar = Calendar.current
    let days = Int(jsRound(calendar.startOfDay(for: today).timeIntervalSince(calendar.startOfDay(for: d)) / 86400))
    if days == 0 { return "Today, \(time)" }
    if days == 1 { return "Yesterday, \(time)" }
    return "\(dayFmt.string(from: d)), \(time)"
}

// "Today" for the dashboard's heading, like Thursday, October 22
private let todayFmt: DateFormatter = {
    let format = DateFormatter()
    format.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
    return format
}()

// The dashboard is the Today screen. It shows what's left to do today, as shortcuts into the other tabs
@MainActor
@Observable
final class DashboardModel {
    unowned let app: AppModel
    var records: [AssessmentRecord] = []
    // Today's suggested exercise and its level, and whether any practice happened today
    var focus: Practice.Focus? = nil
    var focusLevel = ""
    var practicedToday = false

    init(app: AppModel) { self.app = app }

    func onShow() {
        // The dose button here shares Care's medicine and last dose
        app.care.refresh()
        Task {
            do {
                records = try await Store.listAssessments()
            } catch {
                print("NeuroTrace: couldn't read history", error)
                records = []
            }
            let tries = (try? await Store.listTrainingTries()) ?? []
            let next = Practice.focus(latest: records.first, lastPracticed: Practice.lastPracticed(tries))
            focusLevel = Copy.levelShort((Store.getTrainingState(next.exercise)?.level ?? 0) + 1)
            focus = next
            practicedToday = Practice.doneToday(tries.map { t in t.ts }, now: Date())
        }
    }

    // The newest check-in, if it was done today
    var todayCheckin: AssessmentRecord? {
        records.first.flatMap { r in Practice.doneToday([r.ts], now: Date()) ? r : nil }
    }
}

struct HistoryRow: View {
    let when: String
    let sub: String
    var mono = false
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if mono {
                        Text(when).nt(.mono(21, 600, lineHeight: 1.3)).foregroundStyle(p.ink.color)
                    } else {
                        Text(when).text(.strong)
                    }
                    Text(sub).text(.sub)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IconView(icon: .chevron, size: 20, weight: 2.2).foregroundStyle(p.ink2.color)
            }
            .padding(.vertical, 12)
            .padding(.leading, mono ? 0 : 20)
            .padding(.trailing, mono ? 0 : 16)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPress())
    }
}

private struct RowPress: ButtonStyle {
    @Environment(\.palette) private var p

    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? p.fill.color : Color.clear)
    }
}

// A round checkmark for things already done today
private struct DoneCheckmark: View {
    @Environment(\.palette) private var p

    var body: some View {
        IconView(icon: .checkmark, size: 20, weight: 2.6)
            .foregroundStyle(p.accent.color)
            .frame(width: 36, height: 36)
            .background(Circle().fill(p.accentSoft.color))
            .accessibilityHidden(true)
    }
}

struct DashboardScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.dashboard
        let wide = typo.width >= 900
        ScreenView(maxWidth: wide ? 1040 : 560, tabbed: true, titled: true) { _ in
            // A phone has no top bar, so the name and the settings button go here
            if !typo.tabsOnTop {
                HStack(spacing: 10) {
                    Mascot(mood: "idle").frame(width: 36, height: 36)
                    Text("NeuroTrace").text(.brand(21))
                    Spacer(minLength: 0)
                    settingsButton
                }
                .frame(minHeight: 44)
            }
            H1(text: "Today", top: typo.tabsOnTop ? 0 : 16)
            Text(todayFmt.string(from: Date())).text(.lede).padding(.top, 6)

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
                checkin(m).padding(.top, 24)
                exercise(m).padding(.top, 16)
                DoseCard(m: app.care, full: false).padding(.top, 16)
            }
            Spacer(minLength: 0)
            LockNote().padding(.top, 24)
        }
    }

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

    // Today's check-in, or what today's check-in found once it's done
    @ViewBuilder
    private func checkin(_ m: DashboardModel) -> some View {
        if let done = m.todayCheckin {
            Card(spacing: 12) {
                HStack(spacing: 12) {
                    DoneCheckmark()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spiral check-in done").text(.cardTitle)
                        Text(historyWhen(done.ts)).text(.sub)
                    }
                }
                if let r = done.result { Text(Copy.tiers[r.tier].label).text(.strong) }
                ButtonPair {
                    Btn(title: "See today's result", kind: .secondary) { app.go(.results, "\(done.id ?? 0)") }
                } second: {
                    Btn(title: "Check in again", kind: .secondary) { app.go(.about) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Spiral check-in")
        } else {
            Card(spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spiral check-in").text(.h1(24, 1.15, 500)).accessibilityAddTraits(.isHeader)
                        Text(Copy.checkinBlurb).text(.lede).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    MiniArt()
                }
                Btn(title: "Start a check-in") { app.go(.about) }
                // The newest check-in from an earlier day, so today still shows where things stood
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
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today's exercise").text(.cardTitle)
                        Text("\(Copy.exerciseNames[focus.exercise] ?? focus.exercise), \(m.focusLevel)").text(.sub)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if m.practicedToday { DoneCheckmark() }
                }
                Text(m.practicedToday ? Copy.practicedToday : focusReason(focus)).text(.body).fixedSize(horizontal: false, vertical: true)
                Btn(title: m.practicedToday ? "Practice again" : "Start", kind: m.practicedToday ? .secondary : .primary) {
                    app.training.open(focus.exercise)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Today's exercise")
        }
    }
}

// The newest check-in, as a row that opens its result
private struct LastCheckin: View {
    let when: String
    let result: String
    let action: () -> Void
    @Environment(\.palette) private var p

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last check-in").text(.sub)
                    Text(when).text(.strong)
                    if !result.isEmpty { Text(result).text(.sub) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IconView(icon: .chevron, size: 20, weight: 2.2).foregroundStyle(p.ink2.color)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.98, dim: true))
        .accessibilityElement(children: .combine)
    }
}

struct Field: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    // Grows to more lines for longer text, like a schedule
    var multiline = false
    @Environment(\.palette) private var p

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).text(.strong).accessibilityHidden(true)
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
