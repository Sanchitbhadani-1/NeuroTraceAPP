// ABOUTSCREEN.SWIFT ASKS FOR YOUR AGE AND YOUR DRAWING HAND BEFORE A CHECK IN
// IT SAVES THE TWO ANSWERS AND THEN OPENS THE DRAWING SCREEN

import SwiftUI

// Holds what the about you screen needs, and saves the answers
@MainActor
@Observable
final class AboutModel {

    // The main app model
    unowned let app: AppModel

    // The age and hand picked so far, or nil if none is picked yet
    var age: String? = nil
    var hand: String? = nil

    // The screen the back link goes to
    var back = Screen.consent

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // True once both an age and a hand are picked
    var ready: Bool { age != nil && hand != nil }

    // Fill in the saved answers and pick where the back link goes when the screen shows
    func onShow() {

        // Use the saved age and hand only if they are still one of the choices
        let prefs = Store.getPrefs()
        age = Copy.ageChoices.contains { c in c.label == prefs.ageChoice } ? prefs.ageChoice : nil
        hand = ["left", "right"].contains(prefs.hand) ? prefs.hand : nil

        // Go back to the tab the person came from, or to the testing tab if they came from somewhere else
        back = app.cameFrom.flatMap { from in AppModel.tabs.contains(from) ? from : nil } ?? .testing
    }

    // Save the answers and open the drawing screen
    func continueTapped() {

        // Stop if the age or the hand is missing
        guard let ageChoice = age, let hand else { return }

        // Save the age and hand
        Store.setPrefs { p in
            p.ageChoice = ageChoice
            p.hand = hand
        }

        // Store the answers and the age group for this check in, then open the drawing screen
        app.choice = Choice(ageChoice: ageChoice, bracket: Copy.ageChoices.first { c in c.label == ageChoice }?.bracket, hand: hand)
        app.go(.draw)
    }
}


// The age choices as value and label pairs for the chips
let ageItems = Copy.ageChoices.map { c in (value: c.label, label: c.label) }


// The about you screen itself
struct AboutScreen: View {

    // The main app model
    @Environment(AppModel.self) private var app

    var body: some View {
        let m = app.about
        ScreenView { _ in

            // The back link and the progress bar at the top, on step 2 of 3
            Bar {
                BackLink { app.go(m.back) }
            } center: {
                Segments(total: 3, done: 1, animateNow: false)
            } right: {
                EmptyView()
            }

            // The title and the line about why the app asks
            H1(text: "About you")
            Text(Copy.aboutWhy).text(.lede).padding(.top, 10)

            // The age chips
            VStack(alignment: .leading, spacing: 0) {
                Legend(text: "Your age")

                // One chip per Copy.ageChoices
                ChipGrid(items: ageItems, selected: m.age) { value in m.age = value }
            }
            .padding(.top, 28)

            // The left hand and right hand chips, and a help line under them
            VStack(alignment: .leading, spacing: 0) {
                Legend(text: "Drawing hand")
                ChipGrid(items: [(value: "left", label: "Left hand"), (value: "right", label: "Right hand")], selected: m.hand) { value in m.hand = value }
            }
            .padding(.top, 28)
            Text(Copy.handHelp).text(.sub).padding(.top, 10)

            // The Continue button at the bottom, turned off until both are picked
            Spacer(minLength: 0)
            Btn(title: "Continue", disabled: !m.ready) { m.continueTapped() }
                .padding(.top, 24)
        }
    }
}
