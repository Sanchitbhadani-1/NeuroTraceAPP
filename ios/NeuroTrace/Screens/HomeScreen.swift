// HOMESCREEN.SWIFT IS THE WELCOME SCREEN PEOPLE SEE BEFORE THEY LOG IN
// IT SHOWS THE ANIMATED SPIRAL, WHAT THE APP DOES, HOW IT WORKS, AND THE LOG IN BUTTONS

import SwiftUI

// Holds what the welcome screen needs, and handles logging in
@MainActor
@Observable
final class HomeModel {

    // The main app model
    unowned let app: AppModel

    // The sentence about who you are compared with, filled in once the scoring files load
    var aboutReference: String? = nil

    // Connect the screen to the main app model
    init(app: AppModel) {
        self.app = app
    }

    // Log in, sending people who haven't agreed yet to the consent screen first
    func login() {

        // If they haven't agreed yet, go to the consent screen
        if !Store.getPrefs().consented {
            app.go(.consent)
            return
        }

        // Save that they're signed in and go to the dashboard
        Store.setPrefs { p in
            p.signedIn = true
        }
        app.go(.dashboard)
    }

    // Load the sentence about who you are compared with in the background when the screen shows
    func onShow() {
        Task {
            do {

                // Wait for the scoring files, then build the sentence from the whole reference group
                let reference = try await app.scoring.value.reference
                let all = reference.brackets["all"]!

                // True only when the reference group drew on the same kind of device as this one
                let deviceMatched = reference.deviceMatched == true

                aboutReference = Copy.referenceSentence(
                    referenceN: all.n,
                    bracketKey: "all",
                    deviceMatched: deviceMatched
                )
            } catch {

                // If the scoring files can't load, leave the sentence out
                aboutReference = nil
            }
        }
    }
}


// The welcome screen itself
struct HomeScreen: View {

    // The app model, colors and text sizes shared by every screen
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    // Which account screen is open, Log in or Create an account, or nil if neither of them are
    @State private var account: AccountScreen.Mode?

    var body: some View {
        let home = app.home
        ScreenView { _ in

            // The logo and the app name at the top
            HStack(spacing: 10) {
                MarkView(size: 28)
                Text("NeuroTrace")
                    .text(.brand(19))
            }
            .frame(minHeight: 44)

            // The animated spiral
            Hero()
                .padding(.top, 20)
                .fullWidth(.center)

            // The headline and a short description of the app
            H1(text: "Measure how you move.", size: 40, lineHeight: 1.08, top: 32)
            Text(Copy.pitch + " " + Copy.tracks)
                .text(.lede)
                .padding(.top, 12)

            // The log in buttons
            VStack(spacing: 10) {

                // With accounts set up, show Log in and Create an account
                if Accounts.ready {
                    ButtonPair {
                        Btn(title: "Log in") {
                            account = .logIn
                        }
                    } second: {
                        Btn(title: "Create an account", kind: .secondary) {
                            account = .create
                        }
                    }
                    Text(Copy.accountNote)
                        .text(.sub)
                        .multilineTextAlignment(.center)
                        .fullWidth(.center)
                } else {

                    // Without accounts, show one Log in button that opens the app on this device
                    Btn(title: "Log in") {
                        home.login()
                    }
                    Text(Copy.loginNote)
                        .text(.sub)
                        .multilineTextAlignment(.center)
                        .fullWidth(.center)
                }
            }
            .padding(.top, 24)

            // A card that says the app is not a diagnosis
            Card {
                Text("What it is not")
                    .text(.cardTitle)
                Text(Copy.notADiagnosis)
                    .text(.body)
            }
            .padding(.top, 24)

            // The How it works steps, one numbered row per step
            Text("How it works")
                .text(.sectionTitle)
                .padding(.top, 28)
            Card(padding: 0, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<Copy.howSteps.count, id: \.self) { i in

                        // A thin line between rows
                        if i > 0 {
                            Hairline()
                        }

                        // The step number in a circle, then the text of the step
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(i + 1)")
                                .nt(.body(nil, 600, lineHeight: 1.2))
                                .foregroundStyle(p.accent.color)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(p.accentSoft.color))
                            Text(Copy.howSteps[i])
                                .text(.body)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 14)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }
            .padding(.top, 12)

            // Who you are compared with, once the sentence has loaded
            Text("Who you are compared with")
                .text(.sectionTitle)
                .padding(.top, 28)
            if let reference = home.aboutReference {
                Card {
                    Text(reference)
                        .text(.body)
                }
                .padding(.top, 12)
            }

            // The privacy note and the credits at the bottom
            LockNote()
                .padding(.top, 24)
            Text(Copy.credit)
                .text(.sub)
                .multilineTextAlignment(.center)
                .fullWidth(.center)
                .padding(.top, 20)
        }
        // Open the account screen over everything when one of the buttons is tapped
        .fullScreenCover(item: $account) { mode in

            // Done closes it and logs in, and close just closes it
            AccountScreen(mode: mode, done: {
                account = nil
                home.login()
            }, close: {
                account = nil
            })
            // Pass the app model, colors and text sizes into the account screen
            .environment(app)
            .environment(\.palette, p)
            .environment(\.typo, typo)
        }
    }
}


// The animated spiral at the top of the welcome screen
private struct Hero: View {

    // The colors and text sizes, and how much of the spiral has been drawn, from 0 to 1
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo
    @State private var drawn: CGFloat = 0

    var body: some View {

        // Make the box 180 to 272 points wide based on the screen's height
        let fitted = typo.height - 572
        let size = min(272, max(180, fitted))

        // Make the spiral a little smaller than the box
        let inner = size * 0.868

        ZStack {

            // A rounded box with a thin border and a soft shadow
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(p.surface.color)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(p.line.color, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 18)

            ZStack {

                // The gray guide spiral
                ArtShape(points: Art.guide)
                    .stroke(p.guide.color, lineWidth: 3 * inner / 340)

                // The hand drawn spiral on top, drawn only as far as the animation has gotten
                ArtShape(points: Art.trace)
                    .trim(from: 0, to: drawn)
                    .stroke(
                        p.accent.color,
                        style: StrokeStyle(
                            lineWidth: 5.5 * inner / 340,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
            .frame(width: inner, height: inner)
        }
        .frame(width: size, height: size)
        // Screen readers read the spiral as one picture with this description
        .accessibilityElement()
        .accessibilityLabel("A spiral traced by hand over the on-screen guide")
        // Draw the spiral when the screen shows
        .onAppear {

            // With Reduced Motion on, show the whole spiral right away
            if Motion.reduced() {
                drawn = 1
                return
            }

            // Draw the spiral in over 2.6 seconds after a short pause, starting fast and slowing down at the end
            withAnimation(.timingCurve(0.22, 1, 0.36, 1, duration: 2.6).delay(0.3)) {
                drawn = 1
            }
        }
    }
}
