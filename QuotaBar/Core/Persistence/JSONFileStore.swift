import Foundation

/// A small Codable value persisted as one JSON file, written atomically.
struct JSONFileStore<Value: Codable & Sendable>: Sendable {
    let url: URL

    /// Returns nil when the file is missing or unreadable; a corrupt cache is
    /// treated the same as no cache.
    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// The latest successful reading per provider, so values survive relaunches
/// and temporary provider failures.
typealias UsageCache = JSONFileStore<[ProviderUsage]>
