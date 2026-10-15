using QuotaBar.Core;

namespace QuotaBar.Providers;

/// Reads Claude usage from the Anthropic account endpoint (default on Windows)
/// or from the snapshot written by the status line bridge.
public sealed class ClaudeUsageProvider(AppPaths paths, ClaudeStatusLineBridge bridge, ClaudeAccountUsageSource accountSource, Func<ClaudeSource> source)
    : IUsageProvider
{
    public AIProvider Provider => AIProvider.Claude;

    public Task<ProviderUsage> FetchUsageAsync(CancellationToken cancellationToken)
    {
        if (source() == ClaudeSource.Account)
            return accountSource.FetchAsync(cancellationToken);
        return Task.Run(ReadSnapshot, cancellationToken);
    }

    private ProviderUsage ReadSnapshot()
    {
        if (!bridge.IsInstalled())
        {
            if (!Directory.Exists(paths.ClaudeDirectory)) throw ProviderException.CliNotInstalled("Claude Code");
            throw ProviderException.NotConfigured("Claude isn't connected yet");
        }
        if (!File.Exists(paths.ClaudeSnapshotFile))
            throw ProviderException.NoUsageData("Waiting for Claude Code — send a message in a terminal session");

        var capturedAt = new DateTimeOffset(File.GetLastWriteTimeUtc(paths.ClaudeSnapshotFile), TimeSpan.Zero);
        return ClaudeUsageParser.ParseStatusLine(File.ReadAllText(paths.ClaudeSnapshotFile), capturedAt);
    }
}
