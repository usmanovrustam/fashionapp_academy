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

    private let wardrobeRepository: WardrobeRepository
    private let imageStorage: ImageStorage
    private let analytics: AnalyticsTracking
    let statisticsUseCase: ComputeWardrobeStatisticsUseCase

    init(container: AppContainer) {
        self.wardrobeRepository = container.wardrobeRepository
        self.imageStorage = container.imageStorage
        self.analytics = container.analytics
        self.statisticsUseCase = container.statisticsUseCase
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
