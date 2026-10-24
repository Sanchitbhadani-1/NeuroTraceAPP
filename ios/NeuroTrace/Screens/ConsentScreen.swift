import SwiftUI

@MainActor
@Observable
final class ConsentModel {
    unowned let app: AppModel
    var boxes = [false, false]

    init(app: AppModel) { self.app = app }

    var ready: Bool { boxes.allSatisfy { box in box } }

    func onShow() {
        let consented = Store.getPrefs().consented
        boxes = [consented, consented]
    }

    func continueTapped() {
        // With accounts on, only someone who has logged in gets past this screen
        if Accounts.ready && !Accounts.signedIn { return app.go(.home) }
        Store.setPrefs { p in
            p.consented = true
            p.onboarded = true
            p.signedIn = true
        }
        app.go(.dashboard)
    }
}

struct ConsentScreen: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.consent
        ScreenView { _ in
            Bar {
                BackLink { app.go(.home) }
            } center: {
                Segments(total: 3, done: 0, animateNow: false)
            } right: {
                EmptyView()
            }

            H1(text: "Before you start")

            Card {
                Text(Copy.notADiagnosis).text(.body)
                Text(Copy.manyThingsShort).text(.sub)
            }
            .padding(.top, 24)

            Card(padding: 0, spacing: 0) {
                CheckRow(text: Copy.consentUnderstand, checked: m.boxes[0]) { m.boxes[0].toggle() }
                Hairline().padding(.leading, 62)
                CheckRow(text: Copy.consentAdult, checked: m.boxes[1]) { m.boxes[1].toggle() }
            }
            .padding(.top, 16)

            Spacer(minLength: 0)
            VStack(spacing: 12) {
                if !m.ready {
                    Text(Copy.consentHelp).text(.sub).multilineTextAlignment(.center).fullWidth(.center)
                }
                Btn(title: "Continue", disabled: !m.ready) { m.continueTapped() }
            }
            .padding(.top, 24)
        }
    }
}
