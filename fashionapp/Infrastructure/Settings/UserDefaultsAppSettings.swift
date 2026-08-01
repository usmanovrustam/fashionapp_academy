import Foundation

/// Local app preferences. Authentication and wardrobe sync use Firebase only.
@MainActor
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

    var dailyOutfitReminderEnabled: Bool {
        get { defaults.bool(forKey: "dailyOutfitReminderEnabled") }
        set { defaults.set(newValue, forKey: "dailyOutfitReminderEnabled") }
    }

    var dailyOutfitReminderHour: Int {
        get {
            if defaults.object(forKey: "dailyOutfitReminderHour") == nil { return 8 }
            return defaults.integer(forKey: "dailyOutfitReminderHour")
        }
        set { defaults.set(min(23, max(0, newValue)), forKey: "dailyOutfitReminderHour") }
    }

    func clearLocalPreferences() {
        guard let domain = Bundle.main.bundleIdentifier else { return }
        defaults.removePersistentDomain(forName: domain)
    }
}
