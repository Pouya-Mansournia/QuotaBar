import Foundation
import XCTest
@testable import QuotaBar

/// A scratch directory removed when the test finishes.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuotaBarTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Paths rooted entirely inside the scratch directory.
    var paths: AppPaths {
        AppPaths(
            supportDirectory: url.appendingPathComponent("Support/QuotaBar", isDirectory: true),
            homeDirectory: url.appendingPathComponent("Home", isDirectory: true)
        )
    }
}

struct StubLocator: CLILocating {
    var tools: [String: URL] = [:]

    func locate(_ tool: String) async -> URL? {
        tools[tool]
    }
}

/// A provider whose next result can be swapped between refreshes.
final class StubProvider: UsageProvider, @unchecked Sendable {
    let provider: AIProvider
    let dataSourceDescription = "stub"
    private let lock = NSLock()
    private var result: Result<ProviderUsage, Error>

    init(provider: AIProvider, result: Result<ProviderUsage, Error>) {
        self.provider = provider
        self.result = result
    }

    func set(_ result: Result<ProviderUsage, Error>) {
        lock.withLock { self.result = result }
    }

    func fetchUsage() async throws -> ProviderUsage {
        try lock.withLock { result }.get()
    }
}

actor SpyNotifier: UsageNotifying {
    private(set) var delivered: [UsageNotification] = []

    func deliver(_ notifications: [UsageNotification]) async {
        delivered += notifications
    }
}

extension Date {
    /// 2026-10-13 12:00:00 UTC, a Tuesday.
    static let reference = Date(timeIntervalSince1970: 1_791_892_800)
}

func makeUsage(
    _ provider: AIProvider = .claude,
    fiveHour: Double,
    weekly: Double? = nil,
    resetsAt: Date? = Date.reference.addingTimeInterval(3600),
    updatedAt: Date = .reference
) -> ProviderUsage {
    var windows = [UsageWindow(type: .fiveHour, usedPercentage: fiveHour, resetsAt: resetsAt)]
    if let weekly {
        windows.append(UsageWindow(type: .weekly, usedPercentage: weekly, resetsAt: Date.reference.addingTimeInterval(3 * 86400)))
    }
    return ProviderUsage(provider: provider, windows: windows, updatedAt: updatedAt)
}

func XCTAssertThrowsProviderError<T>(
    _ expression: @autoclosure () throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ check: (ProviderError) -> Void
) {
    XCTAssertThrowsError(try expression(), file: file, line: line) { error in
        guard let error = error as? ProviderError else {
            return XCTFail("Expected ProviderError, got \(error)", file: file, line: line)
        }
        check(error)
    }
}
