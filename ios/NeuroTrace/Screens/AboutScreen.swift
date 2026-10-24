import SwiftUI

@MainActor
@Observable
final class AboutModel {
    unowned let app: AppModel
    var age: String? = nil
    var hand: String? = nil
    var back = Screen.consent

    init(app: AppModel) { self.app = app }

    var ready: Bool { age != nil && hand != nil }

    func onShow() {
        let prefs = Store.getPrefs()
        age = Copy.ageChoices.contains { c in c.label == prefs.ageChoice } ? prefs.ageChoice : nil
        hand = ["left", "right"].contains(prefs.hand) ? prefs.hand : nil
        back = app.cameFrom.flatMap { from in AppModel.tabs.contains(from) ? from : nil } ?? .testing
    }

    func continueTapped() {
        guard let ageChoice = age, let hand else { return }
        Store.setPrefs { p in
            p.ageChoice = ageChoice
            p.hand = hand
        }
        app.choice = Choice(ageChoice: ageChoice, bracket: Copy.ageChoices.first { c in c.label == ageChoice }?.bracket, hand: hand)
        app.go(.draw)
    }
}

let ageItems = Copy.ageChoices.map { c in (value: c.label, label: c.label) }

struct AboutScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.about
        ScreenView { _ in
            Bar {
                BackLink { app.go(m.back) }
            } center: {
                Segments(total: 3, done: 1, animateNow: false)
            } right: {
                EmptyView()
            }

            H1(text: "About you")
            Text(Copy.aboutWhy).text(.lede).padding(.top, 10)

            VStack(alignment: .leading, spacing: 0) {
                Legend(text: "Your age")
                // one chip per Copy.ageChoices
                ChipGrid(items: ageItems, selected: m.age) { value in m.age = value }
            }
            .padding(.top, 28)

            VStack(alignment: .leading, spacing: 0) {
                Legend(text: "Drawing hand")
                ChipGrid(items: [(value: "left", label: "Left hand"), (value: "right", label: "Right hand")], selected: m.hand) { value in m.hand = value }
            }
            .padding(.top, 28)
            Text(Copy.handHelp).text(.sub).padding(.top, 10)

            Spacer(minLength: 0)
            Btn(title: "Continue", disabled: !m.ready) { m.continueTapped() }
                .padding(.top, 24)
        }
    }
}
