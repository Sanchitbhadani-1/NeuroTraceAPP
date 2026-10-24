import Foundation
#if canImport(FirebaseCore)
import FirebaseCore
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif

// Starts Firebase once, for accounts and the home scan. Needs GoogleService-Info.plist in the app.
// DEBUG builds use the App Check debug token, release builds use App Attest
@MainActor
enum Cloud {
    static let ready: Bool = {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return false }
        #if canImport(FirebaseAppCheck)
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        #endif
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        return true
    }()
}
#else
// Without the Firebase package there are no accounts and no home scan
@MainActor
enum Cloud {
    static let ready = false
}
#endif
