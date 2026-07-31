import Foundation

// MARK: - Auth

enum AccountAvailability: Equatable {
    case unknown
    case checking
    case available
    case unavailable(String?)
}

protocol AccountStatusProviding: AnyObject {
    var status: AccountAvailability { get }
    func refresh() async -> AccountAvailability
}

// MARK: - Weather & Location

protocol LocationProviding: AnyObject {
    func currentCoordinate() async throws -> (latitude: Double, longitude: Double)
    func reverseGeocode(latitude: Double, longitude: Double) async throws -> String
}

protocol WeatherProviding: AnyObject {
    func currentWeather() async throws -> WeatherSnapshot
    func dailyForecast(days: Int) async throws -> [DailyWeatherForecast]
}

// MARK: - Computer Vision Pipeline

protocol ClothingDetector: AnyObject {
    func detectCategory(in imageData: Data) async throws -> (ClothingCategory, Double)
}

protocol ClothingSegmenter: AnyObject {
    /// Returns a soft mask (alpha channel) as PNG/JPEG-compatible image data.
    func segment(imageData: Data) async throws -> Data
}

protocol BackgroundRemover: AnyObject {
    func removeBackground(imageData: Data, maskData: Data) async throws -> Data
}

protocol ClothingMetadataExtractor: AnyObject {
    func extract(from imageData: Data, category: ClothingCategory) async throws -> ClothingMetadata
}

struct ClothingMetadata: Equatable {
    var subcategory: String?
    var colorPalette: [String]
    var dominantColor: String?
    var material: Material
    var seasons: [Season]
    var temperatureBands: [TemperatureBand]
    var formalityScore: Double
    var styleTags: [StyleTag]
    var occasions: [Occasion]
    var genderNeutral: Bool
    var suggestedName: String
    var confidence: Double
}

protocol ClothingScanPipeline: AnyObject {
    func scan(imageData: Data) async throws -> ClothingScanResult
}

// MARK: - Recommendations & Assistant

struct RecommendationContext: Equatable {
    var weather: WeatherSnapshot?
    var timeOfDay: Date
    var isWeekend: Bool
    var preferredOccasions: [OutfitOccasion]
    var events: [CalendarEvent]
    var user: UserProfile
}

protocol OutfitRecommending: AnyObject {
    func recommend(
        from wardrobe: [WardrobeItem],
        context: RecommendationContext,
        limit: Int
    ) async throws -> [OutfitRecommendation]
}

protocol StylingAssisting: AnyObject {
    func respond(
        to message: String,
        history: [ChatMessage],
        wardrobe: [WardrobeItem],
        context: RecommendationContext
    ) async throws -> StylingAssistantResponse
}

// MARK: - Notifications / Settings

protocol NotificationScheduling: AnyObject {
    func requestAuthorization() async -> Bool
    func scheduleDailyOutfitReminder(at dateComponents: DateComponents) async throws
}

protocol AppSettingsProviding: AnyObject {
    var didFinishOnboarding: Bool { get set }
    var selectedLanguage: String { get set }
    var usesCelsius: Bool { get set }
    func clearLocalPreferences()
}
