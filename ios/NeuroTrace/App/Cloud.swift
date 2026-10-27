// CLOUD.SWIFT STARTS FIREBASE ONCE FOR ACCOUNTS AND THE HOME SCAN
// IT TURNS ON APP CHECK BEFORE FIREBASE STARTS

import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

// Starts Firebase the first time ready is read
@MainActor
enum Cloud {

    // True once Firebase has started, or false if GoogleService-Info.plist is not in the app
    static let ready: Bool = {

        // Give back false if the app has no GoogleService-Info.plist file
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }

        // Use the App Check debug token in DEBUG builds, and App Attest in release builds
        #if canImport(FirebaseAppCheck)
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        #endif

        // Start Firebase if it has not started yet
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        return true
    }()
}
#else

// Without the Firebase package, ready is always false
@MainActor
enum Cloud {
    static let ready = false
}
#endif
