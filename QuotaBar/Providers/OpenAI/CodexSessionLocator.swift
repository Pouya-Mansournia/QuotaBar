import Foundation

/// Finds the most recently written Codex session logs.
///
/// Codex stores them as `sessions/YYYY/MM/DD/rollout-*.jsonl`, so walking
/// directory names in descending order reaches the newest files first without
/// enumerating the whole history.
struct CodexSessionLocator: Sendable {
    let sessionsDirectory: URL

    func recentRollouts(limit: Int) -> [URL] {
        var candidates: [URL] = []
        collect(in: sessionsDirectory, depth: 0, cap: limit * 2, into: &candidates)

        return candidates
            .map { ($0, Self.modificationDate(of: $0) ?? .distantPast) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    private func collect(in directory: URL, depth: Int, cap: Int, into candidates: inout [URL]) {
        guard depth <= 4, candidates.count < cap,
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: directory,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              )
        else { return }

        for entry in entries.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            guard candidates.count < cap else { return }
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                collect(in: entry, depth: depth + 1, cap: cap, into: &candidates)
            } else if entry.pathExtension == "jsonl", entry.lastPathComponent.hasPrefix("rollout-") {
                candidates.append(entry)
            }
        }
    }
}
