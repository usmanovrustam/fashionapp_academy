import Foundation

struct ScanAndSaveClothingUseCase {
    let pipeline: ClothingScanPipeline
    let imageStorage: ImageStorage
    let wardrobeRepository: WardrobeRepository

    func execute(imageData: Data, overrideName: String? = nil, plannedDate: Date? = nil) async throws -> WardrobeItem {
        let scan = try await pipeline.scan(imageData: imageData)
        let itemID = UUID()

        let originalPath = try await imageStorage.saveImageData(
            scan.originalImageData,
            preferredName: "\(itemID.uuidString)-original.jpg"
        )

        var transparentPath: String?
        if let transparent = scan.transparentImageData {
            transparentPath = try await imageStorage.saveImageData(
                transparent,
                preferredName: "\(itemID.uuidString)-transparent.png"
            )
        }

        let now = Date()
        let item = WardrobeItem(
            id: itemID,
            name: (overrideName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? scan.suggestedName,
            originalImagePath: originalPath,
            transparentImagePath: transparentPath,
            category: scan.detectedCategory,
            subcategory: scan.subcategory,
            colorPalette: scan.colorPalette,
            dominantColor: scan.dominantColor,
            material: scan.material,
            seasons: scan.seasons,
            temperatureBands: scan.temperatureBands,
            formalityScore: scan.formalityScore,
            styleTags: scan.styleTags,
            occasions: scan.occasions,
            genderNeutral: scan.genderNeutral,
            aiConfidence: scan.confidence,
            purchaseDate: nil,
            isFavorite: false,
            wornCount: 0,
            lastWornAt: nil,
            isInLaundry: false,
            notes: nil,
            plannedDate: plannedDate,
            createdAt: now,
            updatedAt: now
        )

        try await wardrobeRepository.save(item)
        return item
    }
}

struct ToggleFavoriteItemUseCase {
    let wardrobeRepository: WardrobeRepository

    func execute(itemID: UUID) async throws -> WardrobeItem {
        guard var item = try await wardrobeRepository.fetchItem(id: itemID) else {
            throw DomainError.itemNotFound
        }
        item.isFavorite.toggle()
        item.updatedAt = Date()
        try await wardrobeRepository.save(item)
        return item
    }
}

struct MarkItemWornUseCase {
    let wardrobeRepository: WardrobeRepository
    let outfitRepository: OutfitRepository

    func execute(itemID: UUID, at date: Date = Date()) async throws {
        guard var item = try await wardrobeRepository.fetchItem(id: itemID) else {
            throw DomainError.itemNotFound
        }
        item.wornCount += 1
        item.lastWornAt = date
        item.updatedAt = date
        try await wardrobeRepository.save(item)
    }
}

struct ComputeWardrobeStatisticsUseCase {
    func execute(items: [WardrobeItem]) -> WardrobeStatistics {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        var categoryCounts: [ClothingCategory: Int] = [:]
        for item in items {
            categoryCounts[item.category, default: 0] += 1
        }

        let mostWorn = items.max(by: { $0.wornCount < $1.wornCount })
        let leastWorn = items.min(by: { $0.wornCount < $1.wornCount })
        let averageFormality = items.isEmpty
            ? 0
            : items.map(\.formalityScore).reduce(0, +) / Double(items.count)

        return WardrobeStatistics(
            totalItems: items.count,
            favoritesCount: items.filter(\.isFavorite).count,
            wornThisWeek: items.filter { ($0.lastWornAt ?? .distantPast) >= weekAgo }.count,
            categoryCounts: categoryCounts,
            mostWornItemID: mostWorn?.id,
            leastWornItemID: leastWorn?.id,
            averageFormality: averageFormality
        )
    }
}

enum DomainError: LocalizedError {
    case itemNotFound
    case invalidImage
    case scanFailed(String)
    case storageFailed(String)
    case weatherUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound: return "Wardrobe item not found."
        case .invalidImage: return "The selected image is invalid."
        case .scanFailed(let message): return "Clothing scan failed: \(message)"
        case .storageFailed(let message): return "Storage error: \(message)"
        case .weatherUnavailable(let message): return "Weather unavailable: \(message)"
        }
    }
}
