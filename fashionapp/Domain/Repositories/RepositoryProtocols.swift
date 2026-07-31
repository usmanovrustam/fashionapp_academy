import Foundation

protocol WardrobeRepository: AnyObject {
    func fetchAll() async throws -> [WardrobeItem]
    func fetchItem(id: UUID) async throws -> WardrobeItem?
    func save(_ item: WardrobeItem) async throws
    func delete(id: UUID) async throws
    func deleteAll() async throws
}

protocol OutfitRepository: AnyObject {
    func fetchAll() async throws -> [Outfit]
    func save(_ outfit: Outfit) async throws
    func delete(id: UUID) async throws
    func fetchFavorites() async throws -> [Outfit]
    func fetchHistory() async throws -> [OutfitHistoryEntry]
    func recordWear(_ entry: OutfitHistoryEntry) async throws
}

protocol UserProfileRepository: AnyObject {
    func load() async throws -> UserProfile
    func save(_ profile: UserProfile) async throws
}

protocol RecommendationRepository: AnyObject {
    func save(_ recommendations: [OutfitRecommendation]) async throws
    func latest(limit: Int) async throws -> [OutfitRecommendation]
}

protocol WeatherCacheRepository: AnyObject {
    func cachedSnapshot() async -> WeatherSnapshot?
    func save(_ snapshot: WeatherSnapshot) async throws
}

protocol EventRepository: AnyObject {
    func fetchEvents(from: Date, to: Date) async throws -> [CalendarEvent]
    func save(_ event: CalendarEvent) async throws
}

protocol PackingListRepository: AnyObject {
    func fetchAll() async throws -> [PackingList]
    func save(_ list: PackingList) async throws
    func delete(id: UUID) async throws
}

protocol ImageStorage: AnyObject {
    func saveImageData(_ data: Data, preferredName: String) async throws -> String
    func loadImageData(at path: String) async throws -> Data
    func deleteImage(at path: String) async throws
}
