// TESTINGSCREEN.SWIFT IS THE TESTING TAB THAT STARTS A SPIRAL CHECK IN OR FINGER TAPPING
// IT ALSO HOLDS THE ERROR SCREEN SHOWN WHEN RESULTS CAN'T LOAD

import SwiftUI

// The testing tab
struct TestingScreen: View {

    // The app model, text sizes and colors shared by every screen
    @Environment(AppModel.self) private var app
    @Environment(\.typo) private var typo
    @Environment(\.palette) private var p

    // Whether the finger tapping test is open
    @State private var tapping = false

    var body: some View {

        // A wider page on screens 900 points wide or more
        ScreenView(maxWidth: typo.width >= 900 ? 760 : 560, tabbed: true, titled: true) { _ in

            // The title and a short description
            H1(text: "Testing")
            Text(Copy.testingBlurb).text(.lede).padding(.top, 10)

            // The spiral check in card, with a small spiral picture and a start button
            Card(spacing: 16) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Spiral check-in").text(.cardTitle)
                        Text(Copy.checkinBlurb).text(.sub).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    MiniArt()
                }
                Btn(title: "Start a check-in") { app.go(.about) }
            }
            .padding(.top, 24)

            // The finger tapping card and its start button
            Card(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Finger tapping").text(.cardTitle)
                    Text(Copy.tapBlurb).text(.sub).fixedSize(horizontal: false, vertical: true)
                }

                // A note on devices too old for hand tracking
                if !HandTracking.newEnoughHere { OldIPadNote() }
                Btn(title: "Start finger tapping") { present { tapping = true } }
            }
            .padding(.top, 16)
        }
        // Open the finger tapping test over everything, and pass in the app model, colors and text sizes
        .fullScreenCover(isPresented: $tapping) {
            TapTestScreen { present { tapping = false } }
                .environment(app)
                .environment(\.palette, p)
                .environment(\.typo, typo)
        }
    }

    // Open or close a full screen test, with no slide when Motion is set to Reduced
    private func present(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = Motion.reduced()
        withTransaction(transaction, change)
    }
}


// The screen shown when results can't load
struct ErrorScreen: View {

    // The app model and colors
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p

    var body: some View {
        ScreenView { _ in

            // The title and the error message
            H1(text: "We can't show results")
            Text(app.loadError.map { e in (e as? NTError)?.message ?? e.localizedDescription } ?? "")
                .nt(.body())
                .foregroundStyle(p.ink.color)
                .padding(.top, 16)

            // A line that says nothing was scored
            Text(Copy.nothingScored).text(.lede).padding(.top, 12)

            // A button back to the dashboard at the bottom
            Spacer(minLength: 0)
            Btn(title: "Dashboard", kind: .secondary) { app.go(.dashboard) }
                .padding(.top, 24)
        }
    }
}
