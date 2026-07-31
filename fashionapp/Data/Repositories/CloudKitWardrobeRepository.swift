import Foundation
import CloudKit

/// Optional CloudKit-backed wardrobe repository.
/// The app currently uses `LocalWardrobeRepository` as the source of truth;
/// this type is wired for future sync without changing feature code.
actor CloudKitWardrobeRepository: WardrobeRepository {
    private let database: CKDatabase
    private let recordType = "WardrobeItem"

    init(containerIdentifier: String = "iCloud.apple.academy.fashionapp") {
        let container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
    }

    func fetchAll() async throws -> [WardrobeItem] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        let (results, _) = try await database.records(matching: query)
        return try results.compactMap { _, result in
            let record = try result.get()
            return try Self.map(record)
        }
    }

    func fetchItem(id: UUID) async throws -> WardrobeItem? {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        do {
            let record = try await database.record(for: recordID)
            return try Self.map(record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    func save(_ item: WardrobeItem) async throws {
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch {
            record = CKRecord(recordType: recordType, recordID: recordID)
        }

        record["name"] = item.name
        record["category"] = item.category.rawValue
        record["subcategory"] = item.subcategory
        record["material"] = item.material.rawValue
        record["formalityScore"] = item.formalityScore
        record["aiConfidence"] = item.aiConfidence
        record["isFavorite"] = item.isFavorite ? 1 : 0
        record["wornCount"] = item.wornCount
        record["genderNeutral"] = item.genderNeutral ? 1 : 0
        record["plannedDate"] = item.plannedDate
        record["colorPalette"] = item.colorPalette
        record["dominantColor"] = item.dominantColor
        record["payloadJSON"] = try JSONEncoder.sylyo.encode(item)

        _ = try await database.save(record)
    }

    func delete(id: UUID) async throws {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        _ = try await database.deleteRecord(withID: recordID)
    }

    func deleteAll() async throws {
        let items = try await fetchAll()
        for item in items {
            try await delete(id: item.id)
        }
    }

    private static func map(_ record: CKRecord) throws -> WardrobeItem {
        if let data = record["payloadJSON"] as? Data {
            return try JSONDecoder.sylyo.decode(WardrobeItem.self, from: data)
        }
        return WardrobeItem.placeholder(
            name: record["name"] as? String ?? "Item",
            category: ClothingCategory(rawValue: record["category"] as? String ?? "") ?? .other
        )
    }
}
