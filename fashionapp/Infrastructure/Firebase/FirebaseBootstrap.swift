import Foundation
import FirebaseCore

/// Configures Firebase once when `GoogleService-Info.plist` is present.
enum FirebaseBootstrap {
    private static var didConfigure = false

    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    @discardableResult
    static func configureIfPossible() -> Bool {
        if didConfigure {
            return isConfigured
        }
        didConfigure = true

        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            #if DEBUG
            print("⚠️ GoogleService-Info.plist missing — Firebase features disabled. Copy GoogleService-Info.plist.example and fill in your Firebase iOS app keys.")
            #endif
            return false
        }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}
