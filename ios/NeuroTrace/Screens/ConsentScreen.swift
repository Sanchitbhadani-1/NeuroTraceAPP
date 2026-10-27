// CONSENTSCREEN.SWIFT SHOWS WHAT THE APP IS NOT AND ASKS PEOPLE TO TICK TWO BOXES
// ONCE BOTH ARE TICKED, CONTINUE SAVES THE AGREEMENT AND OPENS THE DASHBOARD

import SwiftUI

// Holds what the consent screen needs, and saves the agreement
@MainActor
@Observable
final class ConsentModel {

    // The main app model
    unowned let app: AppModel

    // Whether each of the two boxes is ticked
    var boxes = [false, false]

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // True once every box is ticked
    var ready: Bool { boxes.allSatisfy { box in box } }

    // Tick both boxes if the person agreed before, and untick them if not
    func onShow() {
        let consented = Store.getPrefs().consented
        boxes = [consented, consented]
    }

    // Save the agreement and open the dashboard
    func continueTapped() {

        // With accounts on, go back to the welcome screen if nobody is logged in
        if Accounts.ready && !Accounts.signedIn { return app.go(.home) }

        // Save that the person agreed, finished setup and is signed in
        Store.setPrefs { p in
            p.consented = true
            p.onboarded = true
            p.signedIn = true
        }
        app.go(.dashboard)
    }
}


// The consent screen itself
struct ConsentScreen: View {

    // The main app model
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.consent
        ScreenView { _ in

            // The back link and the progress bar at the top, on step 1 of 3
            Bar {
                BackLink { app.go(.home) }
            } center: {
                Segments(total: 3, done: 0, animateNow: false)
            } right: {
                EmptyView()
            }

            // The title
            H1(text: "Before you start")

            // A card that says the app is not a diagnosis
            Card {
                Text(Copy.notADiagnosis).text(.body)
                Text(Copy.manyThingsShort).text(.sub)
            }
            .padding(.top, 24)

            // The two boxes to tick, with a thin line between them
            Card(padding: 0, spacing: 0) {
                CheckRow(text: Copy.consentUnderstand, checked: m.boxes[0]) { m.boxes[0].toggle() }
                Hairline().padding(.leading, 62)
                CheckRow(text: Copy.consentAdult, checked: m.boxes[1]) { m.boxes[1].toggle() }
            }
            .padding(.top, 16)

            // The Continue button at the bottom
            Spacer(minLength: 0)
            VStack(spacing: 12) {

                // A help line while a box is still unticked
                if !m.ready {
                    Text(Copy.consentHelp).text(.sub).multilineTextAlignment(.center).fullWidth(.center)
                }
                Btn(title: "Continue", disabled: !m.ready) { m.continueTapped() }
            }
            .padding(.top, 24)
        }
    }
}
