import Foundation

/// Product analytics events designed for Firebase Analytics → BigQuery export
/// and mirrored into Firestore `analyticsEvents` for richer SQL analysis.
enum AnalyticsEventName: String {
    case appOpen = "app_open"
    case signUp = "sign_up"
    case login = "login"
    case logout = "logout"
    case screenView = "screen_view"
    case scanStarted = "scan_started"
    case scanCompleted = "scan_completed"
    case itemSaved = "item_saved"
    case itemFavorited = "item_favorited"
    case itemDeleted = "item_deleted"
    case recommendationViewed = "recommendation_viewed"
    case recommendationAccepted = "recommendation_accepted"
    case recommendationRejected = "recommendation_rejected"
    case assistantAsked = "assistant_asked"
    case assistantReplied = "assistant_replied"
    case weatherLoaded = "weather_loaded"
    case profileUpdated = "profile_updated"
    case onboardingCompleted = "onboarding_completed"
}

struct AnalyticsEvent: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var userId: String?
    var parameters: [String: String]
    var createdAt: Date
    var platform: String
    var appVersion: String

    static func make(
        _ name: AnalyticsEventName,
        userId: String?,
        parameters: [String: String] = [:]
    ) -> AnalyticsEvent {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return AnalyticsEvent(
            id: UUID(),
            name: name.rawValue,
            userId: userId,
            parameters: parameters,
            createdAt: Date(),
            platform: "ios",
            appVersion: version
        )
    }
}

protocol AnalyticsTracking: AnyObject {
    func track(_ name: AnalyticsEventName, parameters: [String: String])
    func setUserID(_ userID: String?)
    func setUserProperty(_ value: String?, forName name: String)
}

extension AnalyticsTracking {
    func track(_ name: AnalyticsEventName) {
        track(name, parameters: [:])
    }
}
