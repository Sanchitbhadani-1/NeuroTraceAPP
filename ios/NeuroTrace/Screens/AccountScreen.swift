// ACCOUNTSCREEN.SWIFT IS THE LOG IN AND CREATE AN ACCOUNT SCREEN
// IT OPENS FULL SCREEN FROM THE WELCOME SCREEN AND CAN SEND A PASSWORD RESET LINK

import SwiftUI
import UIKit

// The log in or create an account screen
struct AccountScreen: View {

    // Which form shows, Log in or Create an account
    enum Mode: String, Identifiable {
        case logIn, create
        var id: String { rawValue }
    }

    // The form that shows now
    @State var mode: Mode

    // What to do once someone is signed in, and what to do when the screen closes
    let done: () -> Void
    let close: () -> Void

    // The colors
    @Environment(\.palette) private var p

    // What is typed in the boxes, whether a request is running, and the message to show
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var message: String?

    // The email with spaces taken off the ends, and true when it has an @ and a password is typed
    private var address: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filled: Bool { address.contains("@") && !password.isEmpty }

    var body: some View {
        ScreenView { _ in

            // The back link, title and a short description for the form that shows
            BackLink { close() }
            H1(text: mode == .logIn ? "Log in" : "Create an account")
            Text(mode == .logIn ? Copy.accountLogInLede : Copy.accountCreateLede)
                .text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 12)

            // The email and password boxes
            VStack(alignment: .leading, spacing: 16) {
                AccountField(label: "Email", text: $email)
                AccountField(label: "Password", text: $password, secure: true)
            }
            .padding(.top, 24)

            // The message, if there is one
            if let message { StatusBox(sentence: message, shake: 0) }

            // The main button, which is off while working or until both boxes are filled
            Btn(title: working ? "One moment\u{2026}" : mode == .logIn ? "Log in" : "Create account", disabled: working || !filled) {
                Task { await submit() }
            }
            .padding(.top, 24)

            // Forgot password on the log in form, and a link to switch forms
            HStack {
                if mode == .logIn {
                    BarLink(label: "Forgot password?") { Task { await reset() } }
                }
                Spacer(minLength: 12)

                // Switch to the other form and clear the message
                BarLink(label: mode == .logIn ? "Create an account" : "I already have an account") {
                    mode = mode == .logIn ? .create : .logIn
                    message = nil
                }
            }
            .disabled(working)
            .padding(.top, 8)

            // The privacy note at the bottom
            Text(Copy.accountPrivacy).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
        }
        .background(p.bg.color.ignoresSafeArea())
    }

    // Logs in or creates the account, then calls done, or shows the error
    private func submit() async {

        // Do nothing if a request is already running
        if working { return }
        working = true
        message = nil
        defer { working = false }

        // Log in or create the account based on the form that shows
        do {
            if mode == .logIn {
                try await Accounts.logIn(address, password)
            } else {
                try await Accounts.create(address, password)
            }
            done()
        } catch {
            show(error.localizedDescription)
        }
    }

    // Sends a password reset link to the email typed above
    private func reset() async {

        // Ask for an email first if the box has no @
        guard address.contains("@") else { return show(Copy.accountNeedEmail) }
        working = true
        defer { working = false }

        // Send the link and say it was sent, or show the error
        do {
            try await Accounts.resetPassword(address)
            show(Copy.accountResetSent(address))
        } catch {
            show(error.localizedDescription)
        }
    }

    // Shows a message and reads it out to screen reader users
    private func show(_ sentence: String) {
        message = sentence
        UIAccessibility.post(notification: .announcement, argument: sentence)
    }
}


// An email or password box, styled like the app's other fields
// The password box has a Show and Hide button
private struct AccountField: View {

    // The label, the typed text, and whether this is a password box
    let label: String
    @Binding var text: String
    var secure = false

    // The colors
    @Environment(\.palette) private var p

    // True while the password shows as plain text
    @State private var showing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // The label above the box, hidden from screen readers
            Text(label).text(.strong).accessibilityHidden(true)
            HStack(spacing: 8) {

                // A hidden password box, or a plain text box with the email keyboard for the email
                Group {
                    if secure && !showing {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                            .keyboardType(secure ? .default : .emailAddress)
                    }
                }
                // Mark the box as a password or an email, with no capitals and no autocorrect
                .textContentType(secure ? .password : .emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .nt(.body())
                .foregroundStyle(p.ink.color)
                .accessibilityLabel(label)

                // The Show and Hide button on the password box
                if secure {
                    BarLink(label: showing ? "Hide" : "Show", strong: true) { showing.toggle() }
                        .accessibilityLabel(showing ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, 16)
            // Use 6 points of padding above and below on the password box, and 14 on the email box
            .padding(.vertical, secure ? 6 : 14)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.surface.color))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.guide.color, lineWidth: p.hair))
        }
    }
}
