import Foundation
import CloudKit
import UIKit

struct Outfit: Identifiable, Hashable {
    let id: CKRecord.ID
    let name: String
    let imageAsset: CKAsset?
    var image: UIImage?
    var plannedDate: Date?

    init(record: CKRecord) {
        self.id = record.recordID
        self.name = record["name"] as? String ?? ""
        self.imageAsset = record["image"] as? CKAsset
        self.image = nil
        self.plannedDate = record["plannedDate"] as? Date
    }

    static func == (lhs: Outfit, rhs: Outfit) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

class OutfitCloudKitManager: ObservableObject {
    static let shared = OutfitCloudKitManager()
    
    @Published var outfits: [Outfit] = []
    @Published var isLoading = false
    @Published var error: Error? = nil
    
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let imageLoadingQueue = DispatchQueue(label: "com.fashionapp.imageloading", qos: .userInitiated)
    private var imageLoadingTasks: [CKRecord.ID: DispatchWorkItem] = [:]
    
    private init() {
        container = CKContainer(identifier: "iCloud.apple.academy.fashionapp")
        privateDatabase = container.privateCloudDatabase
        
        #if DEBUG
        print("📦 CloudKit Manager initialized in DEVELOPMENT environment")
        #else
        print("📦 CloudKit Manager initialized in PRODUCTION environment")
        #endif
        
        print("📦 Container identifier: \(container.containerIdentifier ?? "unknown")")
        print("📦 Database scope: \(privateDatabase.databaseScope == .private ? "private" : "public")")
        
        // Check CloudKit status on initialization
        checkCloudKitStatus()
    }

    func fetchOutfits() {
        print("📦 Starting to fetch outfits from CloudKit...")
        
        // Cancel any existing image loading tasks
        imageLoadingTasks.values.forEach { $0.cancel() }
        imageLoadingTasks.removeAll()
        
        DispatchQueue.main.async {
            print("📦 Setting isLoading = true")
            self.isLoading = true
            self.error = nil
        }
        
        // Use a simple predicate that doesn't require queryable fields
        let query = CKQuery(recordType: "Outfit", predicate: NSPredicate(value: true))
        
        privateDatabase.perform(query, inZoneWith: nil) { [weak self] records, error in
            guard let self = self else { return }
            print("📦 CloudKit fetch completed. Records count: \(records?.count ?? 0)")
            
            if let error = error {
                print("📦 CloudKit fetch error: \(error.localizedDescription)")
                
                // Check for specific schema-related errors
                if error.localizedDescription.contains("queryable") || 
                   error.localizedDescription.contains("Unknown item") || 
                   error.localizedDescription.contains("recordType") ||
                   (error as NSError).code == 12 { // CKErrorUnknownItem
                    print("📦 Detected schema issue, attempting to resolve...")
                    self.createSchemaIfNeeded()
                    return // Don't set error yet, let schema setup complete
                }
                
            DispatchQueue.main.async {
                self.isLoading = false
                    self.error = error
                }
                } else if let records = records {
                print("📦 Successfully fetched \(records.count) outfit records")
                
                // Sort records by modification date in memory instead of in query
                let sortedRecords = records.sorted { record1, record2 in
                    guard let date1 = record1.modificationDate,
                          let date2 = record2.modificationDate else {
                        return false
                    }
                    return date1 > date2
                }
                
                var loadedOutfits = sortedRecords.map { Outfit(record: $0) }
                
                DispatchQueue.main.async {
                    print("📦 Setting outfits array with \(loadedOutfits.count) items")
                    self.outfits = loadedOutfits
                    self.isLoading = false
                    
                    print("📦 Manager state after setting outfits:")
                    print("📦   - isLoading: \(self.isLoading)")
                    print("📦   - outfits.count: \(self.outfits.count)")
                    print("📦   - error: \(self.error?.localizedDescription ?? "none")")
                }
                
                    // Load images asynchronously
                    for (idx, outfit) in loadedOutfits.enumerated() {
                    guard let asset = outfit.imageAsset, let fileURL = asset.fileURL else { 
                        print("📦 No image asset for outfit: \(outfit.name)")
                        continue 
                    }
                    
                    // Create a work item for image loading
                    let workItem = DispatchWorkItem { [weak self] in
                        guard let self = self else { return }
                        
                        if let data = try? Data(contentsOf: fileURL),
                           let img = UIImage(data: data) {
                                DispatchQueue.main.async {
                                    if idx < self.outfits.count, self.outfits[idx].id == outfit.id {
                                        self.outfits[idx].image = img
                                    print("📦 Loaded image for outfit: \(outfit.name)")
                                }
                            }
                        }
                    }
                    
                    // Store the work item and start loading
                    imageLoadingTasks[outfit.id] = workItem
                    imageLoadingQueue.async(execute: workItem)
                    }
                } else {
                print("📦 No records returned from CloudKit")
                DispatchQueue.main.async {
                    self.outfits = []
                    self.isLoading = false
                }
            }
        }
    }
    
    private func createSchemaIfNeeded() {
        print("📦 Creating CloudKit schema by saving a sample record...")
        print("📦 Container identifier: \(container.containerIdentifier ?? "unknown")")
        print("📦 Database type: \(privateDatabase.databaseScope == .private ? "private" : "public")")
        
        // Keep loading state during schema setup
        DispatchQueue.main.async {
            self.isLoading = true
            self.error = nil
        }
        
        // Create a temporary record to establish the schema
        let schemaRecord = CKRecord(recordType: "Outfit")
        schemaRecord["name"] = "Schema Setup Record - Will be deleted"
        
        // Create a small placeholder image for schema setup
        let placeholderImage = UIImage(systemName: "tshirt.fill") ?? UIImage()
        if let imageData = placeholderImage.pngData() {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("schema_setup.png")
            do {
                try imageData.write(to: tempURL)
                let asset = CKAsset(fileURL: tempURL)
                schemaRecord["image"] = asset
                print("📦 Schema setup image asset created at: \(tempURL.path)")
            } catch {
                print("📦 Failed to create schema image: \(error)")
            }
        }
        
        print("📦 Attempting to save schema record...")
        privateDatabase.save(schemaRecord) { record, error in
            if let error = error {
                print("📦 Schema setup failed with error: \(error)")
                print("📦 Error domain: \((error as NSError).domain)")
                print("📦 Error code: \((error as NSError).code)")
                print("📦 Error description: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.error = error
                }
            } else {
                print("📦 Schema setup successful, record ID: \(record?.recordID.recordName ?? "unknown")")
                // Delete the temporary record
                if let recordID = record?.recordID {
                    self.privateDatabase.delete(withRecordID: recordID) { _, deleteError in
                        if let deleteError = deleteError {
                            print("📦 Failed to delete schema setup record: \(deleteError)")
                        } else {
                            print("📦 Schema setup complete, temporary record deleted")
                        }
                        
                        // Try fetching again after schema setup
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            print("📦 Retrying fetch after schema setup...")
                            self.fetchOutfits()
                        }
                    }
                }
            }
        }
    }
    
    func saveOutfit(name: String, image: UIImage, plannedDate: Date? = nil, completion: @escaping (Result<CKRecord, Error>) -> Void) {
        print("Starting to save outfit: \(name)")
        
        let record = CKRecord(recordType: "Outfit")
        record["name"] = name
        if let plannedDate = plannedDate {
            record["plannedDate"] = plannedDate
        }
        
        // Save image as CKAsset
        if let imageData = image.jpegData(compressionQuality: 0.8) {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            do {
                try imageData.write(to: tempURL)
                let asset = CKAsset(fileURL: tempURL)
                record["image"] = asset
                print("Image asset created for outfit: \(name)")
            } catch {
                print("Failed to write image data: \(error)")
                completion(.failure(error))
                return
            }
        }
        
        privateDatabase.save(record) { savedRecord, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("CloudKit save error: \(error)")
                    completion(.failure(error))
                } else if let savedRecord = savedRecord {
                    print("CloudKit save success: \(savedRecord)")
                    completion(.success(savedRecord))
                    // Refresh the outfits list after a short delay to allow CloudKit to propagate
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.fetchOutfits()
                    }
                } else {
                    print("Unknown CloudKit save error")
                    completion(.failure(NSError(domain: "CloudKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown save error"])))
                }
            }
        }
    }
    
    func checkCloudKitStatus() {
        container.accountStatus { [weak self] status, error in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch status {
                case .available:
                    print("📦 CloudKit account status: Available")
                    self.fetchOutfits()
                case .noAccount:
                    print("📦 CloudKit account status: No Account")
                    self.error = NSError(domain: "CloudKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "No iCloud account found. Please sign in to iCloud in Settings."])
                case .restricted:
                    print("📦 CloudKit account status: Restricted")
                    self.error = NSError(domain: "CloudKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "iCloud access is restricted."])
                case .couldNotDetermine:
                    print("📦 CloudKit account status: Could Not Determine")
                    self.error = error ?? NSError(domain: "CloudKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not determine iCloud status."])
                @unknown default:
                    print("📦 CloudKit account status: Unknown")
                    self.error = NSError(domain: "CloudKit", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown iCloud status."])
                }
            }
        }
    }
} 