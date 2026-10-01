import Foundation

enum Store {

    struct Prefs: Codable, Equatable {
        var onboarded = false
        var consented = false
        var signedIn = false
        var ageChoice: String? = nil
        var hand = "right"
        var theme = "auto"
        var accent = "blue"
        var motion = "auto"
    }

    static var defaults = UserDefaults.standard

    static let prefsKey = "neurotrace:prefs"
    static let prefsDefaults = Prefs(onboarded: false, consented: false, signedIn: false, ageChoice: nil, hand: "right", theme: "auto", accent: "blue", motion: "auto")

    static func getPrefs() -> Prefs {
        do {
            let raw = defaults.string(forKey: prefsKey)
            return raw != nil ? try JSONDecoder().decode(Prefs.self, from: Data(raw!.utf8)) : prefsDefaults
        } catch {
            return prefsDefaults
        }
    }

    static func setPrefs(_ patch: (inout Prefs) -> Void) {
        do {
            var prefs = getPrefs()
            patch(&prefs)
            defaults.set(String(decoding: try JSONEncoder().encode(prefs), as: UTF8.self), forKey: prefsKey)
        } catch {
        }
    }
}

extension Store.Prefs {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = Store.Prefs()
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? base.onboarded
        consented = try c.decodeIfPresent(Bool.self, forKey: .consented) ?? base.consented
        signedIn = try c.decodeIfPresent(Bool.self, forKey: .signedIn) ?? base.signedIn
        ageChoice = try c.decodeIfPresent(String.self, forKey: .ageChoice) ?? base.ageChoice
        hand = try c.decodeIfPresent(String.self, forKey: .hand) ?? base.hand
        theme = try c.decodeIfPresent(String.self, forKey: .theme) ?? base.theme
        accent = try c.decodeIfPresent(String.self, forKey: .accent) ?? base.accent
        motion = try c.decodeIfPresent(String.self, forKey: .motion) ?? base.motion
    }
}
