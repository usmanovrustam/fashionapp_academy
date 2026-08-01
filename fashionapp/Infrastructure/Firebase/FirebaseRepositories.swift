import Foundation
import FirebaseFirestore

actor FirebaseWardrobeRepository: WardrobeRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchAll() async throws -> [WardrobeItem] {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let snapshot = try await db.collection(FirestorePaths.wardrobe(uid: uid)).getDocuments()
        return try snapshot.documents.map {
            try FirestoreCoding.decode(WardrobeItem.self, from: $0.data())
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    func fetchItem(id: UUID) async throws -> WardrobeItem? {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let document = try await db.collection(FirestorePaths.wardrobe(uid: uid)).document(id.uuidString).getDocument()
        guard let data = document.data() else { return nil }
        return try FirestoreCoding.decode(WardrobeItem.self, from: data)
    }

    func save(_ item: WardrobeItem) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let payload = try FirestoreCoding.encode(item)
        try await db.collection(FirestorePaths.wardrobe(uid: uid))
            .document(item.id.uuidString)
            .setData(payload, merge: true)
    }

    func delete(id: UUID) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        try await db.collection(FirestorePaths.wardrobe(uid: uid)).document(id.uuidString).delete()
    }

    func deleteAll() async throws {
        let items = try await fetchAll()
        for item in items {
            try await delete(id: item.id)
        }
    }
}

actor FirebaseOutfitRepository: OutfitRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchAll() async throws -> [Outfit] {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let snapshot = try await db.collection(FirestorePaths.outfits(uid: uid)).getDocuments()
        return try snapshot.documents.map {
            try FirestoreCoding.decode(Outfit.self, from: $0.data())
        }
    }

    func save(_ outfit: Outfit) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        try await db.collection(FirestorePaths.outfits(uid: uid))
            .document(outfit.id.uuidString)
            .setData(try FirestoreCoding.encode(outfit), merge: true)
    }

    func delete(id: UUID) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        try await db.collection(FirestorePaths.outfits(uid: uid)).document(id.uuidString).delete()
    }

    func fetchFavorites() async throws -> [Outfit] {
        try await fetchAll().filter(\.isFavorite)
    }

    func fetchHistory() async throws -> [OutfitHistoryEntry] {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let snapshot = try await db.collection(FirestorePaths.outfitHistory(uid: uid)).getDocuments()
        return try snapshot.documents.map {
            try FirestoreCoding.decode(OutfitHistoryEntry.self, from: $0.data())
        }
        .sorted { $0.wornAt > $1.wornAt }
    }

    func recordWear(_ entry: OutfitHistoryEntry) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        try await db.collection(FirestorePaths.outfitHistory(uid: uid))
            .document(entry.id.uuidString)
            .setData(try FirestoreCoding.encode(entry), merge: true)

        if var outfit = try await fetchAll().first(where: { $0.id == entry.outfitID }) {
            outfit.wornCount += 1
            outfit.lastWornAt = entry.wornAt
            outfit.updatedAt = entry.wornAt
            try await save(outfit)
        }
    }
}

actor FirebaseUserProfileRepository: UserProfileRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func load() async throws -> UserProfile {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let document = try await db.document(FirestorePaths.profile(uid: uid)).getDocument()
        if let data = document.data() {
            return try FirestoreCoding.decode(UserProfile.self, from: data)
        }
        let profile = UserProfile.default
        // Keep a stable UUID but key profile by Firebase uid via document path.
        try await save(profile)
        return profile
    }

    func save(_ profile: UserProfile) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        var updated = profile
        updated.updatedAt = Date()
        try await db.document(FirestorePaths.profile(uid: uid))
            .setData(try FirestoreCoding.encode(updated), merge: true)
    }
}

actor FirebaseRecommendationRepository: RecommendationRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func save(_ recommendations: [OutfitRecommendation]) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let batch = db.batch()
        let collection = db.collection(FirestorePaths.recommendations(uid: uid))
        for recommendation in recommendations {
            let ref = collection.document(recommendation.id.uuidString)
            batch.setData(try FirestoreCoding.encode(recommendation), forDocument: ref, merge: true)
        }
        try await batch.commit()
    }

    func latest(limit: Int) async throws -> [OutfitRecommendation] {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let snapshot = try await db.collection(FirestorePaths.recommendations(uid: uid))
            .order(by: "generatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        return try snapshot.documents.map {
            try FirestoreCoding.decode(OutfitRecommendation.self, from: $0.data())
        }
    }
}

actor FirebaseEventRepository: EventRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchEvents(from: Date, to: Date) async throws -> [CalendarEvent] {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let snapshot = try await db.collection(FirestorePaths.events(uid: uid)).getDocuments()
        return try snapshot.documents
            .map { try FirestoreCoding.decode(CalendarEvent.self, from: $0.data()) }
            .filter { $0.startDate >= from && $0.startDate <= to }
    }

    func save(_ event: CalendarEvent) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        try await db.collection(FirestorePaths.events(uid: uid))
            .document(event.id.uuidString)
            .setData(try FirestoreCoding.encode(event), merge: true)
    }
}

actor FirebasePackingListRepository: PackingListRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func fetchAll() async throws -> [PackingList] {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        let snapshot = try await db.collection(FirestorePaths.packingLists(uid: uid)).getDocuments()
        return try snapshot.documents.map {
            try FirestoreCoding.decode(PackingList.self, from: $0.data())
        }
    }

    func save(_ list: PackingList) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        try await db.collection(FirestorePaths.packingLists(uid: uid))
            .document(list.id.uuidString)
            .setData(try FirestoreCoding.encode(list), merge: true)
    }

    func delete(id: UUID) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        try await db.collection(FirestorePaths.packingLists(uid: uid)).document(id.uuidString).delete()
    }
}

actor FirebaseWeatherCacheRepository: WeatherCacheRepository {
    private let db: Firestore

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    func cachedSnapshot() async -> WeatherSnapshot? {
        guard let uid = await MainActor.run(body: { AuthSession.shared.userID }) else { return nil }
        guard let data = try? await db.document(FirestorePaths.weatherCache(uid: uid)).getDocument().data() else {
            return nil
        }
        return try? FirestoreCoding.decode(WeatherSnapshot.self, from: data)
    }

    func save(_ snapshot: WeatherSnapshot) async throws {
        let uid = try await MainActor.run { try FirebaseUserContext.requireUID() }
        try await db.document(FirestorePaths.weatherCache(uid: uid))
            .setData(try FirestoreCoding.encode(snapshot), merge: true)
    }
}
