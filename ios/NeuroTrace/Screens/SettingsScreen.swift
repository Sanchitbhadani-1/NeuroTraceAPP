// SETTINGSSCREEN.SWIFT IS THE SETTINGS SCREEN
// IT CHANGES YOUR DETAILS, THE THEME, THE ACCENT COLOR AND MOTION, AND HANDLES YOUR DATA AND ACCOUNT

import SwiftUI
import UIKit

// The ids of the accent colors, in the same order as Copy.accents
let accentIDs = ["blue", "indigo", "violet", "teal", "amber", "rose", "graphite"]

// The name of an accent color, or the first name if the id is not in the list
func accentName(_ id: String) -> String { Copy.accents[max(0, accentIDs.firstIndex(of: id) ?? -1)] }


// THE SETTINGS MODEL

// Holds what the settings screen needs, and saves changes
@MainActor
@Observable
final class SettingsModel {

    // The main app model
    unowned let app: AppModel

    // The saved choices shown on the screen
    var ageChoice: String? = nil
    var hand: String? = nil
    var theme: String? = nil
    var accent: String? = nil
    var accentCurrent = ""
    var motion: String? = nil

    // The message shown after deleting the data
    var deleteStatus = ""

    // The message shown in the Account card when deleting the account fails
    var accountNote: String? = nil

    // True while sample data is being made
    var loadingSample = false

    // True while a confirm, a delete or a share sheet is open, and other taps do nothing
    @ObservationIgnored private var busy = false

    // Connect the screen to the main app model
    init(app: AppModel) { self.app = app }

    // Load the saved choices and clear the messages when the screen shows
    func onShow() {
        let prefs = Store.getPrefs()
        ageChoice = prefs.ageChoice
        hand = prefs.hand
        theme = prefs.theme
        accent = prefs.accent
        accentCurrent = accentName(prefs.accent)
        motion = prefs.motion
        deleteStatus = ""
        accountNote = nil
    }

    // The settings someone can change on this screen
    enum Setting {
        case age, hand, theme, accent, motion
    }

    // Save a new value for a setting, starting any animation at the tapped point
    func change(_ setting: Setting, _ value: String, _ at: CGPoint?) {

        // Get the x and y of the tap, or nil if there is no point or it is zero
        let x = at.flatMap { p in p == .zero ? nil : p.x }, y = at.flatMap { p in p == .zero ? nil : p.y }

        // Save the value and update the screen for each setting
        switch setting {
        case .age:
            Store.setPrefs { p in p.ageChoice = value }
            ageChoice = value
        case .hand:
            Store.setPrefs { p in p.hand = value }
            hand = value
        case .theme:

            // Switch the theme with an animation from the tap
            Store.setPrefs { p in p.theme = value }
            theme = value
            Motion.swap(.theme, x: x, y: y) { self.app.applyTheme(value) }
        case .accent:

            // Switch the accent color with an animation from the tap
            Store.setPrefs { p in p.accent = value }
            accent = value
            accentCurrent = accentName(value)
            Motion.swap(.theme, x: x, y: y) { self.app.applyAccent(value) }
        case .motion:
            Store.setPrefs { p in p.motion = value }
            motion = value
            Motion.applyMotion(value)
        }

        // Show a Saved message
        Motion.toast(Copy.saved)
    }

    // Ask first, then delete all the personal data on this device
    func deleteAll() async {

        // Do nothing if something else is open, and mark busy until this ends
        if busy { return }
        busy = true
        defer { busy = false }

        // Stop if they don't confirm
        if !(await confirm(Copy.deleteConfirm, Copy.deleteConfirmDetail, action: "Delete")) { return }

        // Delete the data, clear the current check in, and reload the details
        do {
            try await Store.clearPersonalData()
            app.current = nil
            app.choice = nil
            let prefs = Store.getPrefs()
            ageChoice = prefs.ageChoice
            hand = prefs.hand
            deleteStatus = Copy.deleted
        } catch {

            // If it fails, print the error and show the failed message
            print("NeuroTrace: couldn't delete the data", error)
            deleteStatus = Copy.deleteFailed
        }

        // Have screen readers read the message out
        UIAccessibility.post(notification: .announcement, argument: deleteStatus)
    }

    // Log out and go back to the welcome screen
    func logout() {
        Accounts.logOut()
        Store.setPrefs { p in p.signedIn = false }
        app.current = nil
        app.go(.home)
    }

    #if DEBUG
    // Ask first, then replace this device's data with made up sample data, only in debug builds
    func loadSampleData() async {

        // Do nothing if something else is open, and mark busy until this ends
        if busy { return }
        busy = true
        defer { busy = false }

        // Stop if they don't confirm
        if !(await confirm(Copy.sampleConfirm, Copy.sampleConfirmDetail, action: "Replace")) { return }

        // Mark the sample data as loading until this ends
        loadingSample = true
        defer { loadingSample = false }

        // Wait for the scoring files, make the sample data, and reload the screen
        do {
            let scoring = try await app.scoring.value
            try await DemoData.load(model: scoring.model, reference: scoring.reference)
            app.current = nil
            app.choice = nil
            onShow()
            Motion.toast(Copy.sampleLoaded)
        } catch {

            // If it fails, print the error and show a failed message
            print("NeuroTrace: couldn't load the sample data", error)
            Motion.toast(Copy.sampleFailed, ok: false)
        }
    }
    #endif

    // Ask first, then remove the account from Firebase, keeping the check ins on this device
    func deleteAccount() async {

        // Do nothing if something else is open, and mark busy until this ends
        if busy { return }
        busy = true
        defer { busy = false }
        accountNote = nil

        // Stop if they don't confirm
        if !(await confirm(Copy.accountDeleteConfirm, Copy.accountDeleteDetail, action: "Delete")) { return }

        // Delete the account, sign out, and go to the welcome screen
        do {
            try await Accounts.delete()
            Store.setPrefs { p in p.signedIn = false }
            app.current = nil
            Motion.toast(Copy.accountDeleted)
            app.go(.home)
        } catch {

            // If it fails, show the error and have screen readers read it out
            accountNote = error.localizedDescription
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }

    // Save the practice tries to a JSON file and open the share sheet
    func exportPractice() async {

        // Do nothing if something else is open, and mark busy until this ends
        if busy { return }
        busy = true
        defer { busy = false }

        // Load the practice tries, or show a message and stop if there are none
        let tries = (try? await Store.listTrainingTries()) ?? []
        if tries.isEmpty { return Motion.toast(Copy.noPractice, ok: false) }

        // What goes in the file
        struct Body: Encodable {
            var formatVersion = 1
            var exportedAt: String
            var tries: [TrainingTry]
        }

        // Make the file, named with today's date, and share it
        let body = Body(exportedAt: isoNow(), tries: tries)
        let file = ExportFile(name: "neurotrace-practice-\(body.exportedAt.prefix(10)).json", data: jsonForExport(body, pretty: false))
        if await shareFile(file) { Motion.toast(Copy.exported) }
    }
}


// THE SCREEN

// The settings screen itself
struct SettingsScreen: View {

    // The app model, colors and text sizes shared by every screen
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.settings

        // Use a wider page on wide screens
        ScreenView(maxWidth: typo.width >= 900 ? 1040 : 560, tabbed: true, titled: true) { _ in

            // The headline
            H1(text: "Settings")

            // On wide screens, show the sections in two columns
            if typo.width >= 900 {
                HStack(alignment: .top, spacing: 32) {

                    // The left column with your details and appearance
                    VStack(alignment: .leading, spacing: 0) {
                        details(m, first: true)
                        appearance(m)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // The right column with motion, data, researchers and account
                    VStack(alignment: .leading, spacing: 0) {
                        motion(m, first: true)
                        data(m)
                        researchers(m)
                        account(m)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {

                // On narrow screens, show every section in one column
                details(m, first: false)
                appearance(m)
                motion(m, first: false)
                data(m)
                researchers(m)
                account(m)
            }
        }
    }

    // A section title, with less space above it at the top of a wide column
    private func section(_ title: String, first: Bool = false) -> some View {
        Text(title).text(.sectionTitle).padding(.top, first && typo.width >= 900 ? 20 : 28).padding(.bottom, 12)
    }

    // The Your details section
    private func details(_ m: SettingsModel, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Your details", first: first)
            Card {

                // The age group chips, one chip per Copy.ageChoices
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Age group")
                    ChipGrid(items: ageItems, selected: m.ageChoice) { value in m.change(.age, value, nil) }
                }

                // The drawing hand chips
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Drawing hand")
                    ChipGrid(items: [(value: "left", label: "Left hand"), (value: "right", label: "Right hand")], selected: m.hand) { value in m.change(.hand, value, nil) }
                }
                .padding(.top, 16)

                // The help text under the details
                Text(Copy.settingsDetailsHelp).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
    }

    // The Appearance section
    private func appearance(_ m: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Appearance")
            Card {

                // The theme buttons
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Theme")
                    Segmented(options: [(value: "auto", label: "Automatic"), (value: "light", label: "Light"), (value: "dark", label: "Dark")], selected: m.theme) { value, at in
                        m.change(.theme, value, at)
                    }
                }
                Text(Copy.appearanceHelp).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 10)

                // The accent color swatches, one swatch per Copy.accents
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Accent color", value: m.accentCurrent)
                    HStack(spacing: 0) {
                        ForEach(0..<accentIDs.count, id: \.self) { i in
                            swatch(accentIDs[i], Copy.accents[i], checked: m.accent == accentIDs[i]) { at in m.change(.accent, accentIDs[i], at) }
                        }
                    }
                    .padding(.horizontal, -6)
                    .padding(.top, 8)
                }
                .padding(.top, 28)
                Text(Copy.accentHelp).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
    }

    // One round accent color button, with a ring and a checkmark when it is picked
    private func swatch(_ id: String, _ name: String, checked: Bool, _ pick: @escaping (CGPoint) -> Void) -> some View {
        let color = p.swatch(id).color
        return ZStack {

            // The color circle
            Circle().fill(color).frame(width: 32, height: 32)

            // The ring and checkmark, popping in when picked
            if checked {
                Circle().strokeBorder(color, lineWidth: 2).frame(width: 42, height: 42)
                IconView(icon: .checkmark, size: 16, weight: 3).foregroundStyle(Color.white)
                    .transition(.scale(scale: 0).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        // Pick the color with the tap's point on screen
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .global) { location in pick(location) }
        // Animate the checkmark unless Reduced Motion is on
        .animation(Motion.reduced() ? nil : Theme.ease(260), value: checked)
        // Screen readers read it as a button with the color name, and pick it with no point
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { pick(.zero) }
    }

    // The Motion section
    private func motion(_ m: SettingsModel, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Motion", first: first)
            Card {

                // The motion buttons and the help text
                Segmented(options: [(value: "auto", label: "Automatic"), (value: "full", label: "Full"), (value: "reduce", label: "Reduced")], selected: m.motion) { value, at in
                    m.change(.motion, value, at)
                }
                .accessibilityLabel("Motion")
                Text(Copy.motionHelp).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
    }

    // The Your data section
    private func data(_ m: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Your data")
            Card {

                // The help text, the delete button, and the message after deleting
                Text(Copy.deleteHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                Btn(title: "Delete all my data", kind: .secondary) { Task { await m.deleteAll() } }
                if !m.deleteStatus.isEmpty { Text(m.deleteStatus).text(.sub).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    // The For researchers section
    private func researchers(_ m: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("For researchers")
            Card {

                // The button to open collection mode
                Text(Copy.collectionHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                Btn(title: "Open collection mode", kind: .secondary) { app.go(.collect) }

                // The button to export the practice tries
                Text(Copy.practiceExportHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                Btn(title: "Export practice tries", kind: .secondary) { Task { await m.exportPractice() } }

                // The button to load sample data, only in debug builds
                #if DEBUG
                Text(Copy.sampleHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                Btn(title: m.loadingSample ? Copy.sampleLoading : "Load sample data", kind: .secondary, disabled: m.loadingSample) {
                    Task { await m.loadSampleData() }
                }
                #endif
            }
        }
    }

    // The Account section
    private func account(_ m: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Account")
            Card {

                // With an account, show the email, Log out and Delete account, and any error
                if let email = Accounts.email {
                    Text(Copy.signedInAs(email)).text(.strong).fixedSize(horizontal: false, vertical: true)
                    Text(Copy.accountLogoutHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                    ButtonPair {
                        Btn(title: "Log out", kind: .secondary) { m.logout() }
                    } second: {
                        Btn(title: "Delete account", kind: .secondary) { Task { await m.deleteAccount() } }
                    }
                    if let note = m.accountNote { Text(note).text(.sub).fixedSize(horizontal: false, vertical: true) }
                } else {

                    // Without an account, show the help text and Log out
                    Text(Copy.logoutHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                    Btn(title: "Log out", kind: .secondary) { m.logout() }
                }
            }
        }
    }
}
