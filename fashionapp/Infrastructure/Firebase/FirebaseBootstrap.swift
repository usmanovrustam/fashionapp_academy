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
        // Already live — common when AppDelegate configured before App.init.
        if FirebaseApp.app() != nil {
            didAttemptConfigure = true
            return true
        }

        if didAttemptConfigure {
            return false
        }
        didAttemptConfigure = true

        guard FirebaseConfig.isConfigured else {
            #if DEBUG
            print("⚠️ Missing \(FirebaseConfig.plistFileName). Place your Firebase download at \(FirebaseConfig.relativePathInRepo).")
            #endif
            return false
        }

        FirebaseApp.configure()

        #if DEBUG
        if let projectID = FirebaseConfig.projectID {
            print("✅ Firebase configured for project: \(projectID)")
        }
        #endif
        return FirebaseApp.app() != nil
    }
}
