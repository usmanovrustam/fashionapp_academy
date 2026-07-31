import Foundation
import FirebaseCore

/// Configures Firebase once from the real `GoogleService-Info.plist`
/// located at `FirebaseConfig.relativePathInRepo`.
enum FirebaseBootstrap {
    private static var didAttemptConfigure = false

    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    @discardableResult
    static func configureIfPossible() -> Bool {
        if didAttemptConfigure {
            return isConfigured
        }
        didAttemptConfigure = true

        guard FirebaseConfig.isConfigured else {
            #if DEBUG
            print("⚠️ Missing \(FirebaseConfig.plistFileName). Place your Firebase download at \(FirebaseConfig.relativePathInRepo). CloudKit wardrobe storage has been removed.")
            #endif
            return false
        }

        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        #if DEBUG
        if let projectID = FirebaseConfig.projectID {
            print("✅ Firebase configured for project: \(projectID)")
        }
        #endif
        return true
    }
}
