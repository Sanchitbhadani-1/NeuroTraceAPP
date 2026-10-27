// ACCOUNTS.SWIFT LOGS PEOPLE IN AND OUT WITH AN EMAIL AND PASSWORD USING FIREBASE
// IT ALSO CREATES AND DELETES ACCOUNTS, AND TURNS FIREBASE ERRORS INTO PLAIN SENTENCES

import Foundation
#if canImport(FirebaseAuth)
import FirebaseAuth

// Email and password accounts with Firebase Authentication
// An account only signs someone in, and their check ins stay on the device
@MainActor
enum Accounts {

    // True when Firebase is set up
    static var ready: Bool { Cloud.ready }

    // The signed in email, or nil when nobody is signed in, and whether anyone is signed in
    static var email: String? { ready ? Auth.auth().currentUser?.email : nil }
    static var signedIn: Bool { ready && Auth.auth().currentUser != nil }

    // Log in with an email and password
    static func logIn(_ email: String, _ password: String) async throws {
        try await friendly { _ = try await Auth.auth().signIn(withEmail: email, password: password) }
    }

    // Create a new account with an email and password
    static func create(_ email: String, _ password: String) async throws {
        try await friendly { _ = try await Auth.auth().createUser(withEmail: email, password: password) }
    }

    // Send a password reset email to this address
    static func resetPassword(_ email: String) async throws {
        try await friendly { try await Auth.auth().sendPasswordReset(withEmail: email) }
    }

    // Log out of Firebase, and print the error if it fails
    static func logOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("NeuroTrace: couldn't log out of Firebase", error)
        }
    }

    // Delete the signed in account, or do nothing if nobody is signed in
    static func delete() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await friendly { try await user.delete() }
    }

    // Call changed with true or false whenever someone signs in or out, and once at the start
    // Give back the listener, or nil if accounts are not ready
    static func watch(_ changed: @escaping (Bool) -> Void) -> AnyObject? {
        guard ready else { return nil }
        return Auth.auth().addStateDidChangeListener { _, user in changed(user != nil) }
    }

    // Run the work, and if it fails, print the error and throw it again as a plain sentence
    private static func friendly(_ work: () async throws -> Void) async throws {
        do {
            try await work()
        } catch {
            print("NeuroTrace: account problem", error)
            throw AccountError(message: message(error))
        }
    }

    // Pick the sentence from Copy that matches each Firebase error code
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

// Without the FirebaseAuth package, accounts are not ready and every function does nothing
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

// An account error that holds the sentence to show
struct AccountError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
