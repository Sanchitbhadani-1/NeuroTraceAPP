import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth

// Email and password accounts with Firebase Authentication. An account only signs someone in. Their
// check-ins and everything else stay on the device
@MainActor
enum Accounts {
    // Needs Firebase set up and the FirebaseAuth package
    static var ready: Bool { Cloud.ready }

    // The signed in email, or nil when nobody is signed in
    static var email: String? { ready ? Auth.auth().currentUser?.email : nil }
    static var signedIn: Bool { ready && Auth.auth().currentUser != nil }

    static func logIn(_ email: String, _ password: String) async throws {
        try await friendly { _ = try await Auth.auth().signIn(withEmail: email, password: password) }
    }

    static func create(_ email: String, _ password: String) async throws {
        try await friendly { _ = try await Auth.auth().createUser(withEmail: email, password: password) }
    }

    static func resetPassword(_ email: String) async throws {
        try await friendly { try await Auth.auth().sendPasswordReset(withEmail: email) }
    }

    static func logOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("NeuroTrace: couldn't log out of Firebase", error)
        }
    }

    static func delete() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await friendly { try await user.delete() }
    }

    // Calls changed with true or false whenever someone signs in or out, and once at the start.
    // Keep what it returns, or it stops
    static func watch(_ changed: @escaping (Bool) -> Void) -> AnyObject? {
        guard ready else { return nil }
        return Auth.auth().addStateDidChangeListener { _, user in changed(user != nil) }
    }

    // Firebase's errors as a sentence someone can act on
    private static func friendly(_ work: () async throws -> Void) async throws {
        do {
            try await work()
        } catch {
            print("NeuroTrace: account problem", error)
            throw AccountError(message: message(error))
        }
    }

    private static func message(_ error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .invalidEmail, .missingEmail: return Copy.accountBadEmail
        case .emailAlreadyInUse: return Copy.accountTaken
        case .weakPassword: return Copy.accountWeakPassword
        case .wrongPassword, .userNotFound, .invalidCredential: return Copy.accountWrong
        case .networkError: return Copy.accountOffline
        case .tooManyRequests: return Copy.accountTooMany
        case .requiresRecentLogin: return Copy.accountRecentLogin
        case .userDisabled: return Copy.accountDisabled
        case .operationNotAllowed: return Copy.accountNotTurnedOn
        default: return Copy.accountFailed
        }
    }
}
#else
// Without the FirebaseAuth package, Log in just opens the app, like before accounts
@MainActor
enum Accounts {
    static let ready = false
    static var email: String? { nil }
    static var signedIn: Bool { false }
    static func logIn(_ email: String, _ password: String) async throws {}
    static func create(_ email: String, _ password: String) async throws {}
    static func resetPassword(_ email: String) async throws {}
    static func logOut() {}
    static func delete() async throws {}
    static func watch(_ changed: @escaping (Bool) -> Void) -> AnyObject? { nil }
}
#endif

struct AccountError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
