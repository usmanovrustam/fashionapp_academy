import Foundation

/// Local app preferences. Auth and wardrobe sync use Firebase.
final class UserDefaultsAppSettings: AppSettingsProviding {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var didFinishOnboarding: Bool {
        get { defaults.bool(forKey: "didFinishOnboarding") }
        set { defaults.set(newValue, forKey: "didFinishOnboarding") }
    }

    var selectedLanguage: String {
        get { defaults.string(forKey: "selectedLanguage") ?? (Locale.current.language.languageCode?.identifier ?? "en") }
        set { defaults.set(newValue, forKey: "selectedLanguage") }
    }

    var usesCelsius: Bool {
        get {
            if defaults.object(forKey: "usesCelsius") == nil { return true }
            return defaults.bool(forKey: "usesCelsius")
        }
        set { defaults.set(newValue, forKey: "usesCelsius") }
    }

    func clearLocalPreferences() {
        guard let domain = Bundle.main.bundleIdentifier else { return }
        defaults.removePersistentDomain(forName: domain)
    }
}
