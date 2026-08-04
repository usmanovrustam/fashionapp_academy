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
    /// `nil` until the user chooses during registration or the in-app prompt.
    var gender: UserGender?
    var avatarImagePath: String?
    var createdAt: Date
    var updatedAt: Date

    var hasGenderSet: Bool { gender != nil }

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
            gender: nil,
            avatarImagePath: nil,
            createdAt: now,
            updatedAt: now
        )
    }

    init(
        id: UUID,
        displayName: String,
        preferredLanguage: String,
        usesCelsius: Bool,
        stylePreferences: [StyleTag],
        favoriteColors: [String],
        avoidCategories: [ClothingCategory],
        genderNeutralPreferred: Bool,
        gender: UserGender? = nil,
        avatarImagePath: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredLanguage = preferredLanguage
        self.usesCelsius = usesCelsius
        self.stylePreferences = stylePreferences
        self.favoriteColors = favoriteColors
        self.avoidCategories = avoidCategories
        self.genderNeutralPreferred = genderNeutralPreferred
        self.gender = gender
        self.avatarImagePath = avatarImagePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        preferredLanguage = try container.decode(String.self, forKey: .preferredLanguage)
        usesCelsius = try container.decodeIfPresent(Bool.self, forKey: .usesCelsius) ?? true
        stylePreferences = try container.decodeIfPresent([StyleTag].self, forKey: .stylePreferences) ?? []
        favoriteColors = try container.decodeIfPresent([String].self, forKey: .favoriteColors) ?? []
        avoidCategories = try container.decodeIfPresent([ClothingCategory].self, forKey: .avoidCategories) ?? []
        genderNeutralPreferred = try container.decodeIfPresent(Bool.self, forKey: .genderNeutralPreferred) ?? false
        // Unknown legacy values (e.g. preferNotToSay) → unset so the app prompts again.
        if let raw = try container.decodeIfPresent(String.self, forKey: .gender) {
            gender = UserGender(rawValue: raw)
        } else {
            gender = nil
        }
        avatarImagePath = try container.decodeIfPresent(String.self, forKey: .avatarImagePath)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
