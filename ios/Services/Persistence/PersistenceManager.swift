import Foundation

// MARK: - Persistence Manager (JSON files in Documents directory)
final class PersistenceManager {

    static let shared = PersistenceManager()
    private init() {}

    private var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Save
    func save<T: Codable>(_ value: T, fileName: String) {
        let url = documentsURL.appendingPathComponent("\(fileName).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomicWrite, .completeFileProtection])
        } catch {
            print("[Persistence] ❌ Failed to save \(fileName): \(error)")
        }
    }

    // MARK: - Load
    func load<T: Codable>(fileName: String) -> T? {
        let url = documentsURL.appendingPathComponent("\(fileName).json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            print("[Persistence] ❌ Failed to load \(fileName): \(error)")
            return nil
        }
    }

    // MARK: - Delete
    func delete(fileName: String) {
        let url = documentsURL.appendingPathComponent("\(fileName).json")
        try? FileManager.default.removeItem(at: url)
    }
}
