import SwiftUI
import UIKit

// Log in or create an account. Shown full screen from the welcome screen
struct AccountScreen: View {
    enum Mode: String, Identifiable {
        case logIn, create
        var id: String { rawValue }
    }

    @State var mode: Mode
    // Called once someone is signed in
    let done: () -> Void
    let close: () -> Void
    @Environment(\.palette) private var p
    @State private var email = ""
    @State private var password = ""
    @State private var working = false
    @State private var message: String?

    private var address: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filled: Bool { address.contains("@") && !password.isEmpty }

    var body: some View {
        ScreenView { _ in
            BackLink { close() }
            H1(text: mode == .logIn ? "Log in" : "Create an account")
            Text(mode == .logIn ? Copy.accountLogInLede : Copy.accountCreateLede)
                .text(.lede).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            VStack(alignment: .leading, spacing: 16) {
                AccountField(label: "Email", text: $email)
                AccountField(label: "Password", text: $password, secure: true)
            }
            .padding(.top, 24)
            if let message { StatusBox(sentence: message, shake: 0) }
            Btn(title: working ? "One moment\u{2026}" : mode == .logIn ? "Log in" : "Create account", disabled: working || !filled) {
                Task { await submit() }
            }
            .padding(.top, 24)
            HStack {
                if mode == .logIn {
                    BarLink(label: "Forgot password?") { Task { await reset() } }
                }
                Spacer(minLength: 12)
                BarLink(label: mode == .logIn ? "Create an account" : "I already have an account") {
                    mode = mode == .logIn ? .create : .logIn
                    message = nil
                }
            }
            .disabled(working)
            .padding(.top, 8)
            Text(Copy.accountPrivacy).text(.sub).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
        }
        .background(p.bg.color.ignoresSafeArea())
    }

    private func submit() async {
        if working { return }
        working = true
        message = nil
        defer { working = false }
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

    // Sends a reset link to the email typed above
    private func reset() async {
        guard address.contains("@") else { return show(Copy.accountNeedEmail) }
        working = true
        defer { working = false }
        do {
            try await Accounts.resetPassword(address)
            show(Copy.accountResetSent(address))
        } catch {
            show(error.localizedDescription)
        }
    }

    private func show(_ sentence: String) {
        message = sentence
        UIAccessibility.post(notification: .announcement, argument: sentence)
    }
}

// An email or password box, styled like the app's other fields. The password has Show and Hide
private struct AccountField: View {
    let label: String
    @Binding var text: String
    var secure = false
    @Environment(\.palette) private var p
    // True while the password shows as plain text
    @State private var showing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).text(.strong).accessibilityHidden(true)
            HStack(spacing: 8) {
                Group {
                    if secure && !showing {
                        SecureField("", text: $text)
                    } else {
                        TextField("", text: $text)
                            .keyboardType(secure ? .default : .emailAddress)
                    }
                }
                // Always a plain password, never a new one, so iOS doesn't cover the box with a strong password of its own
                .textContentType(secure ? .password : .emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .nt(.body())
                .foregroundStyle(p.ink.color)
                .accessibilityLabel(label)
                if secure {
                    BarLink(label: showing ? "Hide" : "Show", strong: true) { showing.toggle() }
                        .accessibilityLabel(showing ? "Hide password" : "Show password")
                }
            }
            .padding(.horizontal, 16)
            // Show and Hide are 44 points tall to be easy to tap, so the password box uses less padding to match
            .padding(.vertical, secure ? 6 : 14)
            .frame(minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.surface.color))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.guide.color, lineWidth: p.hair))
        }
    }
}
