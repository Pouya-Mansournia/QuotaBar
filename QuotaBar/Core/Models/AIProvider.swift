import Foundation

/// A usage source QuotaBar knows how to display.
///
/// Adding a provider means adding a case here and a `UsageProvider`
/// implementation; the store, cache, notifications and UI are provider-agnostic.
enum AIProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    /// Single-letter code used in the compact menu bar title.
    var shortCode: String {
        switch self {
        case .claude: "C"
        case .codex: "O"
        }
    }

    var symbolName: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Name of the command-line tool that backs this provider.
    var cliName: String {
        switch self {
        case .claude: "claude"
        case .codex: "codex"
        }
    }
}
