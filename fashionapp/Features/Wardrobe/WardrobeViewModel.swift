import Foundation
import SwiftUI

@MainActor
final class WardrobeViewModel: ObservableObject {
    @Published var items: [WardrobeItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedItem: WardrobeItem?
    @Published var filterCategory: ClothingCategory?
    @Published var showFavoritesOnly = false
    @Published var showLaundryOnly = false
    @Published var userGender: UserGender = .woman

    private let wardrobeRepository: WardrobeRepository
    private let profileRepository: UserProfileRepository
    private let imageStorage: ImageStorage
    private let imageSearch: WardrobeImageSearching?
    private let analytics: AnalyticsTracking
    let statisticsUseCase: ComputeWardrobeStatisticsUseCase

    var filterCategories: [ClothingCategory] {
        userGender.wardrobeFilterCategories
    }

    init(container: AppContainer) {
        self.wardrobeRepository = container.wardrobeRepository
        self.profileRepository = container.profileRepository
        self.imageStorage = container.imageStorage
        self.imageSearch = container.imageSearch
        self.analytics = container.analytics
        self.statisticsUseCase = container.statisticsUseCase
    }

    /// Whether the on-device embedding model is available for visual search.
    var canFindSimilar: Bool { imageSearch != nil }

    /// Finds wardrobe pieces visually similar to `item` using the CoreML
    /// embedding model, ordered most-similar first (excludes the query item).
    func findSimilar(to item: WardrobeItem, limit: Int = 12) async -> [WardrobeItem] {
        guard let imageSearch else { return [] }
        let path = item.transparentImagePath ?? item.originalImagePath
        guard !path.isEmpty,
              let data = try? await imageStorage.loadImageData(at: path) else { return [] }
        let candidates = items.filter { $0.id != item.id }
        guard let ids = try? await imageSearch.search(similarTo: data, in: candidates) else { return [] }
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Array(ids.compactMap { byID[$0] }.prefix(limit))
    }

    var laundryCount: Int {
        items.filter(\.isInLaundry).count
    }

    var filteredItems: [WardrobeItem] {
        items.filter { item in
            if showLaundryOnly { return item.isInLaundry }
            if showFavoritesOnly && !item.isFavorite { return false }
            if let filterCategory, item.category != filterCategory { return false }
            return true
        }
    }

    var statistics: WardrobeStatistics {
        statisticsUseCase.execute(items: items)
    }

    func load(force: Bool = false) async {
        if !force && !items.isEmpty { return }

        let showSpinner = items.isEmpty
        if showSpinner { isLoading = true }
        errorMessage = nil
        analytics.track(.screenView, parameters: ["screen_name": "wardrobe"])
        if let gender = try? await profileRepository.load().gender {
            userGender = gender
            if let filterCategory, !filterCategories.contains(filterCategory) {
                self.filterCategory = nil
            }
        }
        do {
            items = try await wardrobeRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func toggleFavorite(_ item: WardrobeItem) async {
        var updated = item
        updated.isFavorite.toggle()
        updated.updatedAt = Date()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        }
        if selectedItem?.id == item.id {
            selectedItem = updated
        }
        do {
            try await wardrobeRepository.save(updated)
            analytics.track(.itemFavorited, parameters: [
                "item_id": item.id.uuidString,
                "is_favorite": updated.isFavorite ? "true" : "false"
            ])
        } catch {
            errorMessage = error.localizedDescription
            await load(force: true)
        }
    }

    func markWashed(_ item: WardrobeItem) async {
        var updated = item
        updated.isInLaundry = false
        updated.updatedAt = Date()
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = updated
        }
        if selectedItem?.id == item.id {
            selectedItem = updated
        }
        do {
            try await wardrobeRepository.save(updated)
        } catch {
            errorMessage = error.localizedDescription
            await load(force: true)
        }
    }

    func delete(_ item: WardrobeItem) async {
        items.removeAll { $0.id == item.id }
        if selectedItem?.id == item.id {
            selectedItem = nil
        }
        do {
            try await wardrobeRepository.delete(id: item.id)
            if let path = item.transparentImagePath {
                ImageMemoryCache.remove(for: path)
                try? await imageStorage.deleteImage(at: path)
            }
            ImageMemoryCache.remove(for: item.originalImagePath)
            try? await imageStorage.deleteImage(at: item.originalImagePath)
            analytics.track(.itemDeleted, parameters: ["item_id": item.id.uuidString])
        } catch {
            errorMessage = error.localizedDescription
            await load(force: true)
        }
    }

    func imageStorageRef() -> ImageStorage { imageStorage }
}
