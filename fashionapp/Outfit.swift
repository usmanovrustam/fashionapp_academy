import Foundation
import CloudKit
import UIKit

struct Outfit: Identifiable, Hashable {
    let id: CKRecord.ID
    let name: String
    let imageAsset: CKAsset?
    var image: UIImage?

    init(record: CKRecord) {
        self.id = record.recordID
        self.name = record["name"] as? String ?? ""
        self.imageAsset = record["image"] as? CKAsset
        self.image = nil
    }

    static func == (lhs: Outfit, rhs: Outfit) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class OutfitCloudKitManager: ObservableObject {
    @Published var outfits: [Outfit] = []
    @Published var isLoading = false
    @Published var error: Error? = nil

    func fetchOutfits() {
        isLoading = true
        error = nil
        let query = CKQuery(recordType: "Outfit", predicate: NSPredicate(value: true))
        CKContainer.default().privateCloudDatabase.perform(query, inZoneWith: nil) { records, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.error = error
                } else if let records = records {
                    var loadedOutfits = records.map { Outfit(record: $0) }
                    self.outfits = loadedOutfits
                    // Load images asynchronously
                    for (idx, outfit) in loadedOutfits.enumerated() {
                        guard let asset = outfit.imageAsset, let fileURL = asset.fileURL else { continue }
                        DispatchQueue.global(qos: .userInitiated).async {
                            if let data = try? Data(contentsOf: fileURL), let img = UIImage(data: data) {
                                DispatchQueue.main.async {
                                    if idx < self.outfits.count, self.outfits[idx].id == outfit.id {
                                        self.outfits[idx].image = img
                                    }
                                }
                            }
                        }
                    }
                } else {
                    self.outfits = []
                }
            }
        }
    }
} 