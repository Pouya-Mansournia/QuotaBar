import Foundation

protocol CLILocating: Sendable {
    func locate(_ tool: String) async -> URL?
}

/// Finds command-line tools without relying on the GUI app's PATH, which
/// does not include Homebrew or user-local directories.
struct CLILocator: CLILocating {
    var searchDirectories: [String]
    var isExecutable: @Sendable (String) -> Bool
    /// Last resort: asks the user's login shell, which has their real PATH.
    var shellLookup: @Sendable (String) async -> String?

    init(
        searchDirectories: [String] = CLILocator.defaultSearchDirectories(),
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        shellLookup: @escaping @Sendable (String) async -> String? = CLILocator.loginShellLookup
    ) {
        self.searchDirectories = searchDirectories
        self.isExecutable = isExecutable
        self.shellLookup = shellLookup
    }

    func locate(_ tool: String) async -> URL? {
        guard Self.isValidToolName(tool) else { return nil }
        for directory in searchDirectories {
            let candidate = (directory as NSString).appendingPathComponent(tool)
            if isExecutable(candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        if let path = await shellLookup(tool), path.hasPrefix("/"), isExecutable(path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// Tool names are fixed by the app, but reject anything path-like anyway
    /// so a name can never escape the search directories.
    static func isValidToolName(_ tool: String) -> Bool {
        !tool.isEmpty && tool.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "." }
            && tool != "." && tool != ".."
    }

    static func defaultSearchDirectories(home: String = NSHomeDirectory()) -> [String] {
        [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "\(home)/.npm-global/bin",
            "\(home)/.bun/bin",
            "\(home)/.volta/bin",
            "/usr/bin",
        ]
    }

    static let loginShellLookup: @Sendable (String) async -> String? = { tool in
        let shell = URL(fileURLWithPath: "/bin/zsh")
        // The tool name is passed as a positional argument, not interpolated
        // into the command string.
        let result = try? await CLIExecutor().execute(
            executable: shell,
            arguments: ["-l", "-c", "command -v -- \"$1\"", "--", tool],
            timeout: .seconds(5)
        )
        guard let result, result.exitCode == 0 else { return nil }
        // Login scripts may print banners; the resolved path is the last line.
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .last
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
