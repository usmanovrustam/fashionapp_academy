import Foundation
import FirebaseCore

/// Configures Firebase once from the real `GoogleService-Info.plist`
/// located at `FirebaseConfig.relativePathInRepo`.
enum FirebaseBootstrap {
    private static let lock = NSLock()
    private static var didAttemptConfigure = false

    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    @discardableResult
    static func configureIfPossible() -> Bool {
        lock.lock()
        defer { lock.unlock() }

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

        // Prefer explicit options from the bundled plist (clearer than implicit default lookup).
        if let plistURL = FirebaseConfig.plistURLInBundle,
           let options = FirebaseOptions(contentsOfFile: plistURL.path) {
            FirebaseApp.configure(options: options)
        } else {
            FirebaseApp.configure()
        }

        #if DEBUG
        if let projectID = FirebaseConfig.projectID {
            print("✅ Firebase configured for project: \(projectID)")
        }
        #endif
        return FirebaseApp.app() != nil
    }
}
