import Foundation

/// User-reviewed fields from a scan — persisted only when the user confirms Save.
struct ReviewedClothingDraft: Equatable {
    var name: String
    var category: ClothingCategory
    var subcategory: String
    var material: Material
    var dominantColor: String
    var season: Season
    var formalityScore: Double
}

struct ScanAndSaveClothingUseCase {
    let pipeline: ClothingScanPipeline
    let imageStorage: ImageStorage
    let wardrobeRepository: WardrobeRepository

    /// Re-scans then saves (legacy). Prefer `execute(scan:draft:plannedDate:)` after user review.
    func execute(imageData: Data, overrideName: String? = nil, plannedDate: Date? = nil) async throws -> WardrobeItem {
        let scan = try await pipeline.scan(imageData: imageData)
        let draft = ReviewedClothingDraft(
            name: (overrideName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? scan.suggestedName,
            category: scan.detectedCategory,
            subcategory: scan.subcategory ?? "",
            material: scan.material,
            dominantColor: scan.dominantColor ?? "",
            season: scan.seasons.first ?? .allSeason,
            formalityScore: scan.formalityScore
        )
        return try await execute(scan: scan, draft: draft, plannedDate: plannedDate)
    }

    /// Saves a scan using the values the user reviewed — does not re-run detection.
    func execute(
        scan: ClothingScanResult,
        draft: ReviewedClothingDraft,
        plannedDate: Date? = nil
    ) async throws -> WardrobeItem {
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

        let trimmedName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedType = draft.subcategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedColor = draft.dominantColor.trimmingCharacters(in: .whitespacesAndNewlines)
        let seasons = [draft.season]
        let bands = temperatureBands(for: draft.season)

        let now = Date()
        let item = WardrobeItem(
            id: itemID,
            name: trimmedName.isEmpty ? scan.suggestedName : trimmedName,
            originalImagePath: originalPath,
            transparentImagePath: transparentPath,
            category: draft.category,
            subcategory: trimmedType.isEmpty ? nil : trimmedType,
            colorPalette: scan.colorPalette,
            dominantColor: trimmedColor.isEmpty ? scan.dominantColor : trimmedColor,
            material: draft.material,
            seasons: seasons,
            temperatureBands: bands,
            formalityScore: min(1, max(0, draft.formalityScore)),
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

    private func temperatureBands(for season: Season) -> [TemperatureBand] {
        switch season {
        case .winter: return [.freezing, .cold]
        case .autumn: return [.cold, .cool]
        case .spring: return [.cool, .mild]
        case .summer: return [.mild, .warm, .hot]
        case .allSeason: return TemperatureBand.allCases
        }
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
    case noClothingDetected
    case scanFailed(String)
    case storageFailed(String)
    case weatherUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound: return "Wardrobe item not found."
        case .invalidImage: return "The selected image is invalid."
        case .noClothingDetected:
            return NSLocalizedString(
                "No outfit found in this photo. Take another photo of a clothing item.",
                comment: "Scan rejected — no apparel detected"
            )
        case .scanFailed(let message): return "Clothing scan failed: \(message)"
        case .storageFailed(let message): return "Storage error: \(message)"
        case .weatherUnavailable(let message): return "Weather unavailable: \(message)"
        }
    }
}
