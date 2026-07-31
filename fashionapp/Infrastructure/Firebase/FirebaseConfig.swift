import Foundation

/// Single place for Firebase project configuration.
///
/// Put your real downloaded file here:
/// `fashionapp/GoogleService-Info.plist`
///
/// That plist (from Firebase Console → Project settings → Your apps)
/// replaces the old CloudKit / iCloud wardrobe container entirely.
///
/// Wardrobe data path after sign-in:
/// `users/{uid}/wardrobeItems/{itemId}` in Cloud Firestore
/// Images: `users/{uid}/images/...` in Firebase Storage
enum FirebaseConfig {
    static let expectedBundleID = "apple.academy.stylo"
    static let plistResourceName = "GoogleService-Info"
    static let plistFileName = "GoogleService-Info.plist"
    static let relativePathInRepo = "fashionapp/GoogleService-Info.plist"

    /// Firestore collection segment used for wardrobe items.
    static let wardrobeCollection = "wardrobeItems"

    static var plistURLInBundle: URL? {
        Bundle.main.url(forResource: plistResourceName, withExtension: "plist")
    }

    static var isConfigured: Bool {
        plistURLInBundle != nil
    }

    /// Reads PROJECT_ID from the real GoogleService-Info.plist when present.
    static var projectID: String? {
        guard let url = plistURLInBundle,
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return nil
        }
        return dict["PROJECT_ID"] as? String
    }

    static var storageBucket: String? {
        guard let url = plistURLInBundle,
              let dict = NSDictionary(contentsOf: url) as? [String: Any] else {
            return nil
        }
        return dict["STORAGE_BUCKET"] as? String
    }
}
