import Foundation
import CloudKit

@MainActor
final class CloudKitAccountStatusService: ObservableObject, AccountStatusProviding {
    @Published private(set) var status: AccountAvailability = .unknown

    private let container: CKContainer

    init(containerIdentifier: String = "iCloud.apple.academy.fashionapp") {
        self.container = CKContainer(identifier: containerIdentifier)
    }

    func refresh() async -> AccountAvailability {
        status = .checking
        do {
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                status = .available
            case .noAccount:
                status = .unavailable("Sign in to iCloud in Settings to sync your wardrobe.")
            case .restricted:
                status = .unavailable("iCloud access is restricted on this device.")
            case .couldNotDetermine:
                status = .unavailable("Could not determine iCloud status.")
            case .temporarilyUnavailable:
                status = .unavailable("iCloud is temporarily unavailable.")
            @unknown default:
                status = .unavailable("Unknown iCloud status.")
            }
        } catch {
            // Local-first architecture: allow the app to continue offline.
            status = .available
        }
        return status
    }
}

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
