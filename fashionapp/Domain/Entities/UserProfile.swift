import Foundation

struct UserProfile: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var displayName: String
    var preferredLanguage: String
    var usesCelsius: Bool
    var stylePreferences: [StyleTag]
    var favoriteColors: [String]
    var avoidCategories: [ClothingCategory]
    var genderNeutralPreferred: Bool
    var avatarImagePath: String?
    var createdAt: Date
    var updatedAt: Date

    static var `default`: UserProfile {
        let now = Date()
        return UserProfile(
            id: UUID(),
            displayName: "Stylist",
            preferredLanguage: Locale.current.language.languageCode?.identifier ?? "en",
            usesCelsius: true,
            stylePreferences: [.casual, .minimalist],
            favoriteColors: [],
            avoidCategories: [],
            genderNeutralPreferred: false,
            avatarImagePath: nil,
            createdAt: now,
            updatedAt: now
        )
    }
}
