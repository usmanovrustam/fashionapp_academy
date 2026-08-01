import Foundation
import FirebaseAnalytics
import FirebaseFirestore
import FirebaseAuth

/// Dual-writes analytics:
/// 1) Firebase Analytics (native BigQuery export when linked in console)
/// 2) Firestore `users/{uid}/analyticsEvents` (stream to BigQuery via extension)
@MainActor
final class FirebaseAnalyticsTracker: AnalyticsTracking {
    private let db: Firestore

    init(db: Firestore = .firestore()) {
        self.db = db
    }

    func setUserID(_ userID: String?) {
        Analytics.setUserID(userID)
        AuthSession.shared.userID = userID ?? Auth.auth().currentUser?.uid
    }

    func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
    }

    func track(_ name: AnalyticsEventName, parameters: [String: String]) {
        var analyticsParams: [String: Any] = [:]
        for (key, value) in parameters {
            // GA4 param keys max 40 chars; values max 100.
            // Reserved prefixes (`firebase_`, `google_`, `ga_`) are dropped by the SDK.
            let safeKey = String(key.prefix(40))
            let lower = safeKey.lowercased()
            if lower.hasPrefix("firebase_") || lower.hasPrefix("google_") || lower.hasPrefix("ga_") {
                #if DEBUG
                print("Analytics: dropping reserved parameter key '\(safeKey)'")
                #endif
                continue
            }
            analyticsParams[safeKey] = String(value.prefix(100))
        }
        Analytics.logEvent(name.rawValue, parameters: analyticsParams)

        let uid = Auth.auth().currentUser?.uid
        let event = AnalyticsEvent.make(name, userId: uid, parameters: parameters)

        Task {
            await persistToFirestore(event)
        }
    }

    private func persistToFirestore(_ event: AnalyticsEvent) async {
        guard let uid = event.userId ?? Auth.auth().currentUser?.uid else { return }
        do {
            let payload = try FirestoreCoding.encode(event)
            try await db.collection(FirestorePaths.analyticsEvents(uid: uid))
                .document(event.id.uuidString)
                .setData(payload, merge: true)
        } catch {
            #if DEBUG
            print("Analytics Firestore mirror failed: \(error.localizedDescription)")
            #endif
        }
    }
}
