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

    private let wardrobeRepository: WardrobeRepository
    private let imageStorage: ImageStorage
    let statisticsUseCase: ComputeWardrobeStatisticsUseCase

    init(container: AppContainer) {
        self.wardrobeRepository = container.wardrobeRepository
        self.imageStorage = container.imageStorage
        self.statisticsUseCase = container.statisticsUseCase
    }

    var filteredItems: [WardrobeItem] {
        items.filter { item in
            if showFavoritesOnly && !item.isFavorite { return false }
            if let filterCategory, item.category != filterCategory { return false }
            return true
        }
    }

    var statistics: WardrobeStatistics {
        statisticsUseCase.execute(items: items)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
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
        do {
            try await wardrobeRepository.save(updated)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: WardrobeItem) async {
        do {
            try await wardrobeRepository.delete(id: item.id)
            if let path = item.transparentImagePath {
                try? await imageStorage.deleteImage(at: path)
            }
            try? await imageStorage.deleteImage(at: item.originalImagePath)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func imageStorageRef() -> ImageStorage { imageStorage }
}
