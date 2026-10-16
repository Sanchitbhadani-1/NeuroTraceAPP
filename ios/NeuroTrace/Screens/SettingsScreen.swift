import SwiftUI
import UIKit

let accentIDs = ["blue", "indigo", "violet", "teal", "amber", "rose", "graphite"]

func accentName(_ id: String) -> String { Copy.accents[max(0, accentIDs.firstIndex(of: id) ?? -1)] }

@MainActor
@Observable
final class SettingsModel {
    unowned let app: AppModel
    var ageChoice: String? = nil
    var hand: String? = nil
    var theme: String? = nil
    var accent: String? = nil
    var accentCurrent = ""
    var motion: String? = nil
    var deleteStatus = ""
    // Shown in the Account card when deleting the account didn't work
    var accountNote: String? = nil
    // True while a confirm, a delete or a share sheet is up, so a second tap doesn't start another
    @ObservationIgnored private var busy = false

    init(app: AppModel) { self.app = app }

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

    func change(_ setting: Setting, _ value: String, _ at: CGPoint?) {
        let x = at.flatMap { p in p == .zero ? nil : p.x }, y = at.flatMap { p in p == .zero ? nil : p.y }
        switch setting {
        case .age:
            Store.setPrefs { p in p.ageChoice = value }
            ageChoice = value
        case .hand:
            Store.setPrefs { p in p.hand = value }
            hand = value
        case .theme:
            Store.setPrefs { p in p.theme = value }
            theme = value
            Motion.swap(.theme, x: x, y: y) { self.app.applyTheme(value) }
        case .accent:
            Store.setPrefs { p in p.accent = value }
            accent = value
            accentCurrent = accentName(value)
            Motion.swap(.theme, x: x, y: y) { self.app.applyAccent(value) }
        case .motion:
            Store.setPrefs { p in p.motion = value }
            motion = value
            Motion.applyMotion(value)
        }
        Motion.toast(Copy.saved)
    }

    func deleteAll() async {
        if busy { return }
        busy = true
        defer { busy = false }
        if !(await confirm(Copy.deleteConfirm, Copy.deleteConfirmDetail, action: "Delete")) { return }
        do {
            try await Store.clearPersonalData()
            app.current = nil
            app.choice = nil
            let prefs = Store.getPrefs()
            ageChoice = prefs.ageChoice
            hand = prefs.hand
            deleteStatus = Copy.deleted
        } catch {
            print("NeuroTrace: couldn't delete the data", error)
            deleteStatus = Copy.deleteFailed
        }
        UIAccessibility.post(notification: .announcement, argument: deleteStatus)
    }

    func logout() {
        Accounts.logOut()
        Store.setPrefs { p in p.signedIn = false }
        app.current = nil
        app.go(.home)
    }

    // Removes the account from Firebase. Check-ins on this device stay, the same as logging out
    func deleteAccount() async {
        if busy { return }
        busy = true
        defer { busy = false }
        accountNote = nil
        if !(await confirm(Copy.accountDeleteConfirm, Copy.accountDeleteDetail, action: "Delete")) { return }
        do {
            try await Accounts.delete()
            Store.setPrefs { p in p.signedIn = false }
            app.current = nil
            Motion.toast(Copy.accountDeleted)
            app.go(.home)
        } catch {
            accountNote = error.localizedDescription
            UIAccessibility.post(notification: .announcement, argument: error.localizedDescription)
        }
    }

    func exportPractice() async {
        if busy { return }
        busy = true
        defer { busy = false }
        let tries = (try? await Store.listTrainingTries()) ?? []
        if tries.isEmpty { return Motion.toast(Copy.noPractice, ok: false) }
        struct Body: Encodable {
            var formatVersion = 1
            var exportedAt: String
            var tries: [TrainingTry]
        }
        let body = Body(exportedAt: isoNow(), tries: tries)
        let file = ExportFile(name: "neurotrace-practice-\(body.exportedAt.prefix(10)).json", data: jsonForExport(body, pretty: false))
        if await shareFile(file) { Motion.toast(Copy.exported) }
    }
}

struct SettingsScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var p
    @Environment(\.typo) private var typo

    var body: some View {
        let m = app.settings
        ScreenView(maxWidth: typo.width >= 900 ? 1040 : 560, tabbed: true, titled: true) { _ in
            H1(text: "Settings")
            if typo.width >= 900 {
                HStack(alignment: .top, spacing: 32) {
                    VStack(alignment: .leading, spacing: 0) {
                        details(m, first: true)
                        appearance(m)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 0) {
                        motion(m, first: true)
                        data(m)
                        researchers(m)
                        account(m)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                details(m, first: false)
                appearance(m)
                motion(m, first: false)
                data(m)
                researchers(m)
                account(m)
            }
        }
    }

    private func section(_ title: String, first: Bool = false) -> some View {
        Text(title).text(.sectionTitle).padding(.top, first && typo.width >= 900 ? 20 : 28).padding(.bottom, 12)
    }

    private func details(_ m: SettingsModel, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Your details", first: first)
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Age group")
                    // one chip per Copy.ageChoices
                    ChipGrid(items: ageItems, selected: m.ageChoice) { value in m.change(.age, value, nil) }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Drawing hand")
                    ChipGrid(items: [(value: "left", label: "Left hand"), (value: "right", label: "Right hand")], selected: m.hand) { value in m.change(.hand, value, nil) }
                }
                .padding(.top, 16)
                Text(Copy.settingsDetailsHelp).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
    }

    private func appearance(_ m: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Appearance")
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Theme")
                    Segmented(options: [(value: "auto", label: "Automatic"), (value: "light", label: "Light"), (value: "dark", label: "Dark")], selected: m.theme) { value, at in
                        m.change(.theme, value, at)
                    }
                }
                Text(Copy.appearanceHelp).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                VStack(alignment: .leading, spacing: 0) {
                    Legend(text: "Accent color", value: m.accentCurrent)
                    // one swatch per Copy.accents
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

    private func swatch(_ id: String, _ name: String, checked: Bool, _ pick: @escaping (CGPoint) -> Void) -> some View {
        let color = p.swatch(id).color
        return ZStack {
            Circle().fill(color).frame(width: 32, height: 32)
            if checked {
                Circle().strokeBorder(color, lineWidth: 2).frame(width: 42, height: 42)
                IconView(icon: .checkmark, size: 16, weight: 3).foregroundStyle(Color.white)
                    .transition(.scale(scale: 0).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .global) { location in pick(location) }
        .animation(Motion.reduced() ? nil : Theme.ease(260), value: checked)
        .accessibilityElement()
        .accessibilityLabel(name)
        .accessibilityAddTraits(checked ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { pick(.zero) }
    }

    private func motion(_ m: SettingsModel, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Motion", first: first)
            Card {
                Segmented(options: [(value: "auto", label: "Automatic"), (value: "full", label: "Full"), (value: "reduce", label: "Reduced")], selected: m.motion) { value, at in
                    m.change(.motion, value, at)
                }
                .accessibilityLabel("Motion")
                Text(Copy.motionHelp).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
    }

    private func data(_ m: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Your data")
            Card {
                Text(Copy.deleteHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                Btn(title: "Delete all my data", kind: .secondary) { Task { await m.deleteAll() } }
                if !m.deleteStatus.isEmpty { Text(m.deleteStatus).text(.sub).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }

    private func researchers(_ m: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("For researchers")
            Card {
                Text(Copy.collectionHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                Btn(title: "Open collection mode", kind: .secondary) { app.go(.collect) }
                Text(Copy.practiceExportHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                Btn(title: "Export practice tries", kind: .secondary) { Task { await m.exportPractice() } }
            }
        }
    }

    private func account(_ m: SettingsModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Account")
            Card {
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
                    Text(Copy.logoutHelp).text(.sub).fixedSize(horizontal: false, vertical: true)
                    Btn(title: "Log out", kind: .secondary) { m.logout() }
                }
            }
        }
    }
}
