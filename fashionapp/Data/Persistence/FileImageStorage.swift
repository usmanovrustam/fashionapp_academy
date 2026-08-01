import Foundation

actor FileImageStorage: ImageStorage {
    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = docs.appendingPathComponent("WardrobeImages", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func saveImageData(_ data: Data, preferredName: String) async throws -> String {
        let safeName = preferredName.replacingOccurrences(of: "/", with: "-")
        let url = directory.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: [.atomic])
            return safeName
        } catch {
            throw DomainError.storageFailed(error.localizedDescription)
        }
    }

    func loadImageData(at path: String) async throws -> Data {
        let url = directory.appendingPathComponent(path)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw DomainError.storageFailed(error.localizedDescription)
        }
    }

    func deleteImage(at path: String) async throws {
        let url = directory.appendingPathComponent(path)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
