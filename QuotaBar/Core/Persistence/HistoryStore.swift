import Foundation

struct HistorySample: Codable, Sendable, Equatable {
    let timestamp: Date
    let provider: AIProvider
    let windowType: UsageWindowType
    let usedPercentage: Double

    var seriesName: String { "\(provider.displayName) \(windowType.shortName)" }
}

/// Local usage history as an append-only JSON Lines file. Never leaves the Mac.
actor HistoryStore {
    private let file: URL
    /// A sample is skipped when the value is unchanged and the previous one is
    /// newer than this, which keeps the file small at short refresh intervals.
    private let minimumInterval: TimeInterval
    private var lastRecorded: [String: HistorySample] = [:]

    init(file: URL, minimumInterval: TimeInterval = 15 * 60) {
        self.file = file
        self.minimumInterval = minimumInterval
    }

    func record(_ usage: ProviderUsage, at now: Date) {
        var lines = Data()
        for window in usage.windows where window.type != .custom {
            let sample = HistorySample(
                timestamp: now,
                provider: usage.provider,
                windowType: window.type,
                usedPercentage: window.effectivePercentage(at: now)
            )
            let key = "\(sample.provider.rawValue).\(sample.windowType.rawValue)"
            if let previous = lastRecorded[key],
               previous.usedPercentage == sample.usedPercentage,
               now.timeIntervalSince(previous.timestamp) < minimumInterval {
                continue
            }
            guard let encoded = try? Self.encoder.encode(sample) else { continue }
            lastRecorded[key] = sample
            lines.append(encoded)
            lines.append(0x0A)
        }
        guard !lines.isEmpty else { return }
        append(lines)
    }

    func samples(since cutoff: Date) -> [HistorySample] {
        loadAll().filter { $0.timestamp >= cutoff }
    }

    /// Rewrites the file without samples older than the retention period.
    func prune(retentionDays: Int, now: Date) {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86400)
        let all = loadAll()
        let kept = all.filter { $0.timestamp >= cutoff }
        guard kept.count != all.count else { return }
        var data = Data()
        for sample in kept {
            guard let encoded = try? Self.encoder.encode(sample) else { continue }
            data.append(encoded)
            data.append(0x0A)
        }
        try? data.write(to: file, options: .atomic)
    }

    func clear() {
        lastRecorded.removeAll()
        try? FileManager.default.removeItem(at: file)
    }

    private func loadAll() -> [HistorySample] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? Self.decoder.decode(HistorySample.self, from: $0) }
    }

    private func append(_ data: Data) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: file.path) {
            try? data.write(to: file, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()
}
