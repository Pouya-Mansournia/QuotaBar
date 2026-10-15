namespace QuotaBar.Core;

/// Every file location QuotaBar touches, in one place so tests can redirect them.
public sealed record AppPaths(string SupportDirectory, string HomeDirectory, string CodexHome)
{
    public static AppPaths Live()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var codexHome = Environment.GetEnvironmentVariable("CODEX_HOME");
        return new AppPaths(
            Path.Combine(appData, "QuotaBar"),
            home,
            string.IsNullOrEmpty(codexHome) ? Path.Combine(home, ".codex") : codexHome);
    }

    public string SettingsFile => Path.Combine(SupportDirectory, "settings.json");
    public string NotificationStateFile => Path.Combine(SupportDirectory, "notification-state.json");

    // Claude
    public string ClaudeDirectory => Path.Combine(HomeDirectory, ".claude");
    public string ClaudeSettingsFile => Path.Combine(ClaudeDirectory, "settings.json");
    /// Claude Code on Windows keeps its sign-in in this file (macOS uses the Keychain).
    public string ClaudeCredentialsFile => Path.Combine(ClaudeDirectory, ".credentials.json");
    public string ClaudeSnapshotFile => Path.Combine(SupportDirectory, "claude-statusline.json");
    public string BridgeScriptFile => Path.Combine(SupportDirectory, "quotabar-statusline.ps1");
    public string BridgeChainFile => Path.Combine(SupportDirectory, "statusline-chain-command");
    public string BridgeOriginalFile => Path.Combine(SupportDirectory, "statusline-original.json");

    // Codex
    public string CodexSessionsDirectory => Path.Combine(CodexHome, "sessions");
    public string CodexAuthFile => Path.Combine(CodexHome, "auth.json");

    public void EnsureSupportDirectory() => Directory.CreateDirectory(SupportDirectory);

    /// Replaces the home directory prefix with `~` for display.
    public string Abbreviated(string path) =>
        path.StartsWith(HomeDirectory, StringComparison.OrdinalIgnoreCase) ? "~" + path[HomeDirectory.Length..] : path;
}
