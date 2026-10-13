import Foundation

/// A source of usage data for one AI tool.
///
/// Implementations must report only what the tool actually exposes and throw
/// a `ProviderError` otherwise — never substitute placeholder values.
protocol UsageProvider: Sendable {
    var provider: AIProvider { get }
    /// One-line description of where the numbers come from, shown in Settings.
    var dataSourceDescription: String { get }

    func fetchUsage() async throws -> ProviderUsage
}

extension UsageProvider {
    var id: String { provider.rawValue }
    var displayName: String { provider.displayName }
}

/// Fetches from a set of providers concurrently and normalizes failures.
struct UsageService: Sendable {
    func fetch(from providers: [any UsageProvider]) async -> [AIProvider: Result<ProviderUsage, ProviderError>] {
        await withTaskGroup(of: (AIProvider, Result<ProviderUsage, ProviderError>).self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        return (provider.provider, .success(try await provider.fetchUsage()))
                    } catch {
                        return (provider.provider, .failure(ProviderError.map(error)))
                    }
                }
            }
            var results: [AIProvider: Result<ProviderUsage, ProviderError>] = [:]
            for await (provider, result) in group {
                results[provider] = result
            }
            return results
        }
    }
}
