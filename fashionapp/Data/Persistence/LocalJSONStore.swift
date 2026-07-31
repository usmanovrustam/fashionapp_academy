import Foundation

/// Lightweight Codable file store used as the default persistence backend.
actor LocalJSONStore {
    private let fileManager: FileManager
    private let rootDirectory: URL

    init(fileManager: FileManager = .default, folderName: String = "SylyoData") {
        self.fileManager = fileManager
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.rootDirectory = base.appendingPathComponent(folderName, isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
    }

    func load<T: Decodable>(_ type: T.Type, from fileName: String) throws -> T? {
        let url = rootDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.sylyo.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, to fileName: String) throws {
        let url = rootDirectory.appendingPathComponent(fileName)
        let data = try JSONEncoder.sylyo.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    func delete(fileName: String) throws {
        let url = rootDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    var directory: URL { rootDirectory }
}

extension JSONEncoder {
    static let sylyo: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}

extension JSONDecoder {
    static let sylyo: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
