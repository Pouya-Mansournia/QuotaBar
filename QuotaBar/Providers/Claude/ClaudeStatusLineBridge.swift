import Foundation

/// Installs and removes the status line script that lets QuotaBar see the
/// rate-limit data Claude Code already computes.
///
/// Claude Code pipes a JSON document to its configured `statusLine` command.
/// The bridge script stores that document's `rate_limits` object in QuotaBar's
/// support directory and then runs whatever status line was configured before,
/// so an existing status line keeps working.
///
/// Installing edits `~/.claude/settings.json`; it only ever happens from an
/// explicit button in Settings, and the previous value is saved for uninstall.
struct ClaudeStatusLineBridge: Sendable {
    enum BridgeError: Error, LocalizedError, Equatable {
        case settingsNotJSON

        var errorDescription: String? {
            switch self {
            case .settingsNotJSON:
                "Claude Code's settings.json is not a JSON object, so QuotaBar left it untouched."
            }
        }
    }

    let paths: AppPaths

    /// The value written to `statusLine.command`.
    var command: String {
        "'" + paths.bridgeScriptFile.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    var backupFile: URL {
        paths.claudeSettingsFile.appendingPathExtension("quotabar-backup")
    }

    func isInstalled() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: paths.bridgeScriptFile.path),
              let settings = try? loadSettings(),
              let statusLine = settings["statusLine"] as? [String: Any]
        else { return false }
        return statusLine["command"] as? String == command
    }

    func install() throws {
        let fileManager = FileManager.default
        try paths.ensureSupportDirectory()
        try Data(Self.script.utf8).write(to: paths.bridgeScriptFile, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.bridgeScriptFile.path)

        var settings = try loadSettings()
        let existing = settings["statusLine"] as? [String: Any]
        if existing?["command"] as? String == command {
            return
        }

        // Remember what was there so uninstall can put it back, and so the
        // script can keep rendering the user's own status line.
        try? fileManager.removeItem(at: paths.bridgeOriginalFile)
        try? fileManager.removeItem(at: paths.bridgeChainFile)
        if let existing {
            let original = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
            try original.write(to: paths.bridgeOriginalFile, options: .atomic)
            if existing["type"] as? String == "command",
               let previousCommand = existing["command"] as? String,
               !previousCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try Data(previousCommand.utf8).write(to: paths.bridgeChainFile, options: .atomic)
            }
        }

        if fileManager.fileExists(atPath: paths.claudeSettingsFile.path) {
            try? fileManager.removeItem(at: backupFile)
            try fileManager.copyItem(at: paths.claudeSettingsFile, to: backupFile)
        }

        var statusLine = existing ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine
        try saveSettings(settings)
    }

    func uninstall() throws {
        let fileManager = FileManager.default
        var settings = try loadSettings()
        if (settings["statusLine"] as? [String: Any])?["command"] as? String == command {
            if let data = try? Data(contentsOf: paths.bridgeOriginalFile),
               let original = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings["statusLine"] = original
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try saveSettings(settings)
        }
        for file in [paths.bridgeScriptFile, paths.bridgeChainFile, paths.bridgeOriginalFile, paths.claudeSnapshotFile] {
            try? fileManager.removeItem(at: file)
        }
    }

    private func loadSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: paths.claudeSettingsFile.path) else {
            return [:]
        }
        let data = try Data(contentsOf: paths.claudeSettingsFile)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
            return [:]
        }
        guard let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BridgeError.settingsNotJSON
        }
        return settings
    }

    private func saveSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(
            at: paths.claudeSettingsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try (data + Data("\n".utf8)).write(to: paths.claudeSettingsFile, options: .atomic)
    }

    /// POSIX sh, using only tools that ship with macOS.
    static let script = #"""
    #!/bin/sh
    # QuotaBar status line bridge. Managed by QuotaBar; remove it from
    # QuotaBar > Settings > Claude rather than editing it.
    #
    # Claude Code pipes its status JSON to this script. The script keeps only the
    # rate_limits object, in a file next to itself, for QuotaBar to read. It makes
    # no network requests and stores nothing else from the payload.

    dir=$(cd "$(dirname "$0")" && pwd) || exit 0
    tmp="$dir/.statusline.$$.tmp"
    out="$dir/.snapshot.$$.tmp"
    trap 'rm -f "$tmp" "$out"' EXIT
    cat > "$tmp" || exit 0

    # rate_limits is absent until the first API response of a session; keep the
    # previous snapshot in that case.
    if limits=$(/usr/bin/plutil -extract rate_limits json -o - "$tmp" 2>/dev/null) && [ -n "$limits" ]; then
      printf '{"rate_limits":%s}\n' "$limits" > "$out" && mv -f "$out" "$dir/claude-statusline.json"
    fi

    if [ -s "$dir/statusline-chain-command" ]; then
      # Hand the untouched payload to the status line that was configured before.
      /bin/sh -c "$(cat "$dir/statusline-chain-command")" < "$tmp"
    else
      model=$(/usr/bin/plutil -extract model.display_name raw -o - "$tmp" 2>/dev/null) || model=""
      five=$(/usr/bin/plutil -extract rate_limits.five_hour.used_percentage raw -o - "$tmp" 2>/dev/null) || five=""
      week=$(/usr/bin/plutil -extract rate_limits.seven_day.used_percentage raw -o - "$tmp" 2>/dev/null) || week=""
      line=${model:-Claude}
      if [ -n "$five" ]; then line="$line · 5h $(printf '%.0f' "$five")%"; fi
      if [ -n "$week" ]; then line="$line · 7d $(printf '%.0f' "$week")%"; fi
      printf '%s\n' "$line"
    fi
    """# + "\n"
}
