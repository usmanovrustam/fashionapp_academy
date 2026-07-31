import Foundation

actor LocalWardrobeRepository: WardrobeRepository {
    private let store: LocalJSONStore
    private let fileName = "wardrobe_items.json"

    init(store: LocalJSONStore) {
        self.store = store
    }

    func fetchAll() async throws -> [WardrobeItem] {
        try await store.load([WardrobeItem].self, from: fileName) ?? []
    }

    func fetchItem(id: UUID) async throws -> WardrobeItem? {
        try await fetchAll().first { $0.id == id }
    }

    func save(_ item: WardrobeItem) async throws {
        var items = try await fetchAll()
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        try await store.save(items, to: fileName)
    }

    func delete(id: UUID) async throws {
        var items = try await fetchAll()
        items.removeAll { $0.id == id }
        try await store.save(items, to: fileName)
    }

    func deleteAll() async throws {
        try await store.save([WardrobeItem](), to: fileName)
    }
}

actor LocalOutfitRepository: OutfitRepository {
    private let store: LocalJSONStore
    private let outfitsFile = "outfits.json"
    private let historyFile = "outfit_history.json"

    init(store: LocalJSONStore) {
        self.store = store
    }

    func fetchAll() async throws -> [Outfit] {
        try await store.load([Outfit].self, from: outfitsFile) ?? []
    }

    func save(_ outfit: Outfit) async throws {
        var outfits = try await fetchAll()
        if let index = outfits.firstIndex(where: { $0.id == outfit.id }) {
            outfits[index] = outfit
        } else {
            outfits.insert(outfit, at: 0)
        }
        try await store.save(outfits, to: outfitsFile)
    }

    func delete(id: UUID) async throws {
        var outfits = try await fetchAll()
        outfits.removeAll { $0.id == id }
        try await store.save(outfits, to: outfitsFile)
    }

    func fetchFavorites() async throws -> [Outfit] {
        try await fetchAll().filter(\.isFavorite)
    }

    func fetchHistory() async throws -> [OutfitHistoryEntry] {
        try await store.load([OutfitHistoryEntry].self, from: historyFile) ?? []
    }

    func recordWear(_ entry: OutfitHistoryEntry) async throws {
        var history = try await fetchHistory()
        history.insert(entry, at: 0)
        try await store.save(history, to: historyFile)

        var outfits = try await fetchAll()
        if let index = outfits.firstIndex(where: { $0.id == entry.outfitID }) {
            outfits[index].wornCount += 1
            outfits[index].lastWornAt = entry.wornAt
            outfits[index].updatedAt = entry.wornAt
            try await store.save(outfits, to: outfitsFile)
        }
    }
}

actor LocalUserProfileRepository: UserProfileRepository {
    private let store: LocalJSONStore
    private let fileName = "user_profile.json"

    init(store: LocalJSONStore) {
        self.store = store
    }

    func load() async throws -> UserProfile {
        if let profile = try await store.load(UserProfile.self, from: fileName) {
            return profile
        }
        let profile = UserProfile.default
        try await store.save(profile, to: fileName)
        return profile
    }

    func save(_ profile: UserProfile) async throws {
        var updated = profile
        updated.updatedAt = Date()
        try await store.save(updated, to: fileName)
    }
}

actor LocalRecommendationRepository: RecommendationRepository {
    private let store: LocalJSONStore
    private let fileName = "recommendations.json"

    init(store: LocalJSONStore) {
        self.store = store
    }

    func save(_ recommendations: [OutfitRecommendation]) async throws {
        try await store.save(recommendations, to: fileName)
    }

    func latest(limit: Int) async throws -> [OutfitRecommendation] {
        let all = try await store.load([OutfitRecommendation].self, from: fileName) ?? []
        return Array(all.prefix(limit))
    }
}

actor LocalWeatherCacheRepository: WeatherCacheRepository {
    private let store: LocalJSONStore
    private let fileName = "weather_cache.json"

    init(store: LocalJSONStore) {
        self.store = store
    }

    func cachedSnapshot() async -> WeatherSnapshot? {
        try? await store.load(WeatherSnapshot.self, from: fileName)
    }

    func save(_ snapshot: WeatherSnapshot) async throws {
        try await store.save(snapshot, to: fileName)
    }
}

actor LocalEventRepository: EventRepository {
    private let store: LocalJSONStore
    private let fileName = "events.json"

    init(store: LocalJSONStore) {
        self.store = store
    }

    func fetchEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        let all = try await store.load([CalendarEvent].self, from: fileName) ?? []
        return all.filter { $0.startDate >= from && $0.startDate <= to }
    }

    func save(_ event: CalendarEvent) async throws {
        var all = try await store.load([CalendarEvent].self, from: fileName) ?? []
        if let index = all.firstIndex(where: { $0.id == event.id }) {
            all[index] = event
        } else {
            all.append(event)
        }
        try await store.save(all, to: fileName)
    }
}

actor LocalPackingListRepository: PackingListRepository {
    private let store: LocalJSONStore
    private let fileName = "packing_lists.json"

    init(store: LocalJSONStore) {
        self.store = store
    }

    func fetchAll() async throws -> [PackingList] {
        try await store.load([PackingList].self, from: fileName) ?? []
    }

    func save(_ list: PackingList) async throws {
        var all = try await fetchAll()
        if let index = all.firstIndex(where: { $0.id == list.id }) {
            all[index] = list
        } else {
            all.insert(list, at: 0)
        }
        try await store.save(all, to: fileName)
    }

    func delete(id: UUID) async throws {
        var all = try await fetchAll()
        all.removeAll { $0.id == id }
        try await store.save(all, to: fileName)
    }
}
