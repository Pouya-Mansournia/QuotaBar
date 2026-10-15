using System.Globalization;
using System.Text;
using System.Text.Json;
using QuotaBar.Core;

namespace QuotaBar.Providers;

/// A rate-limit reading from a Codex session log and the moment Codex recorded it.
public sealed record CodexRateLimitEvent(DateTimeOffset? Timestamp, JsonElement Limits);

/// Extracts rate-limit readings from Codex session logs. Pure; no I/O.
public static class OpenAIUsageParser
{
    /// The general Codex limit. Logs can also carry model-specific limits
    /// under other ids; those are only used when nothing else is present.
    private const string GeneralLimitId = "codex";

    /// Returns the most recent usable rate-limit event in a JSONL log, scanning
    /// from the end. Lines that are not valid JSON are skipped.
    public static CodexRateLimitEvent? LatestEvent(string jsonl)
    {
        CodexRateLimitEvent? fallback = null;
        var lines = jsonl.Split('\n', StringSplitOptions.RemoveEmptyEntries);
        for (var i = lines.Length - 1; i >= 0; i--)
        {
            // Most lines are transcript content; skip them without decoding.
            if (!lines[i].Contains("\"rate_limits\"", StringComparison.Ordinal)) continue;
            JsonElement root;
            try
            {
                using var document = JsonDocument.Parse(lines[i]);
                root = document.RootElement.Clone();
            }
            catch (JsonException)
            {
                continue;
            }
            if (Lenient.Object(root, "payload") is not { } payload || Lenient.Object(payload, "rate_limits") is not { } limits) continue;
            if (UsedPercent(limits, "primary") is null && UsedPercent(limits, "secondary") is null) continue;

            var limitEvent = new CodexRateLimitEvent(Lenient.Date(root, "timestamp"), limits);
            var limitId = Lenient.String(limits, "limit_id");
            if (limitId is null || limitId == GeneralLimitId) return limitEvent;
            fallback ??= limitEvent;
        }
        return fallback;
    }

    private static double? UsedPercent(JsonElement limits, string window) =>
        Lenient.Object(limits, window) is { } element ? Lenient.Number(element, "used_percent") : null;

    /// <param name="recordedAt">Used when the event carries no timestamp.</param>
    public static ProviderUsage Usage(CodexRateLimitEvent limitEvent, DateTimeOffset recordedAt)
    {
        var timestamp = limitEvent.Timestamp ?? recordedAt;
        var windows = new List<UsageWindow>();

        foreach (var name in new[] { "primary", "secondary" })
        {
            if (Lenient.Object(limitEvent.Limits, name) is not { } raw ||
                UsageMath.NormalizedPercentage(Lenient.Number(raw, "used_percent")) is not { } percentage)
                continue;
            var (type, label) = WindowType(Lenient.Number(raw, "window_minutes"));
            if (windows.Any(w => w.Type == type && w.Label == label))
            {
                // Two windows of the same length: keep both distinguishable.
                type = UsageWindowType.Custom;
                label ??= "Secondary";
            }
            // Older Codex versions reported a relative reset instead of resets_at.
            var resetsAt = Lenient.Date(raw, "resets_at")
                ?? (Lenient.Number(raw, "resets_in_seconds") is { } seconds ? timestamp.AddSeconds(seconds) : null);
            windows.Add(new UsageWindow(type, percentage, resetsAt, label));
        }

        if (windows.Count == 0) throw ProviderException.NoUsageData("Codex has not reported usage limits");
        var plan = Lenient.String(limitEvent.Limits, "plan_type");
        return new ProviderUsage(AIProvider.Codex, windows, timestamp,
            string.IsNullOrEmpty(plan) ? null : CultureInfo.InvariantCulture.TextInfo.ToTitleCase(plan));
    }

    /// Maps a window length onto a known window type, or a labelled custom one.
    public static (UsageWindowType Type, string? Label) WindowType(double? minutes)
    {
        if (minutes is not { } value || !double.IsFinite(value) || value <= 0) return (UsageWindowType.Custom, null);
        var rounded = (int)Math.Round(value);
        return rounded switch
        {
            300 => (UsageWindowType.FiveHour, null),
            1440 => (UsageWindowType.Daily, null),
            10080 => (UsageWindowType.Weekly, null),
            >= 40320 and <= 44640 => (UsageWindowType.Monthly, null),
            < 60 => (UsageWindowType.Custom, $"{rounded}m"),
            < 2880 => (UsageWindowType.Custom, $"{rounded / 60}h"),
            _ => (UsageWindowType.Custom, $"{rounded / 1440}d"),
        };
    }
}

/// Reads Codex usage from the rate-limit records the Codex CLI writes to its
/// local session logs. Reads no credentials and makes no network requests.
public sealed class OpenAIUsageProvider(AppPaths paths) : IUsageProvider
{
    public AIProvider Provider => AIProvider.Codex;

    /// How many recent session files to inspect.
    public int SessionLimit { get; init; } = 8;
    /// Rate-limit records are written continuously, so the end of the file is enough.
    public long TailBytes { get; init; } = 256 * 1024;
    public long FullReadLimit { get; init; } = 32 * 1024 * 1024;

    public Task<ProviderUsage> FetchUsageAsync(CancellationToken cancellationToken) => Task.Run(Fetch, cancellationToken);

    private ProviderUsage Fetch()
    {
        if (!Directory.Exists(paths.CodexHome)) throw ProviderException.CliNotInstalled("Codex CLI");

        var files = RecentRollouts(paths.CodexSessionsDirectory, SessionLimit);
        if (files.Count == 0)
        {
            if (!File.Exists(paths.CodexAuthFile)) throw ProviderException.AuthenticationRequired("Codex");
            throw ProviderException.NoUsageData("No Codex sessions found yet");
        }

        (CodexRateLimitEvent Event, DateTimeOffset Date)? latest = null;
        Exception? firstReadError = null;
        foreach (var file in files)
        {
            var modified = new DateTimeOffset(File.GetLastWriteTimeUtc(file), TimeSpan.Zero);
            // Files are newest-first; an older file cannot beat a newer reading.
            if (latest is { } current && modified < current.Date) continue;
            try
            {
                if (LatestEvent(file, TailBytes, FullReadLimit) is not { } found) continue;
                var date = found.Timestamp ?? modified;
                if (latest is null || date > latest.Value.Date) latest = (found, date);
            }
            catch (IOException exception)
            {
                firstReadError ??= exception;
            }
        }

        if (latest is null)
        {
            if (firstReadError is not null) throw new ProviderException(ProviderErrorKind.Unknown, firstReadError.Message);
            throw ProviderException.NoUsageData("Codex has not reported usage limits yet");
        }
        return OpenAIUsageParser.Usage(latest.Value.Event, latest.Value.Date);
    }

    /// Codex stores logs as `sessions/YYYY/MM/DD/rollout-*.jsonl`, so walking
    /// directory names in descending order reaches the newest files first.
    public static List<string> RecentRollouts(string sessionsDirectory, int limit)
    {
        var candidates = new List<string>();
        Collect(sessionsDirectory, 0, limit * 2, candidates);
        return candidates.OrderByDescending(File.GetLastWriteTimeUtc).Take(limit).ToList();
    }

    private static void Collect(string directory, int depth, int cap, List<string> candidates)
    {
        if (depth > 4 || candidates.Count >= cap || !Directory.Exists(directory)) return;
        IEnumerable<string> entries;
        try
        {
            entries = Directory.EnumerateFileSystemEntries(directory).OrderByDescending(Path.GetFileName, StringComparer.Ordinal).ToList();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return;
        }
        foreach (var entry in entries)
        {
            if (candidates.Count >= cap) return;
            var name = Path.GetFileName(entry);
            if (name.StartsWith('.')) continue;
            if (Directory.Exists(entry)) Collect(entry, depth + 1, cap, candidates);
            else if (name.StartsWith("rollout-", StringComparison.Ordinal) && name.EndsWith(".jsonl", StringComparison.Ordinal))
                candidates.Add(entry);
        }
    }

    public static CodexRateLimitEvent? LatestEvent(string file, long tailBytes, long fullReadLimit)
    {
        // Codex keeps the file open while writing; share it.
        using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        var size = stream.Length;
        var offset = size > tailBytes ? size - tailBytes : 0;
        stream.Seek(offset, SeekOrigin.Begin);
        var text = ReadToEnd(stream);
        if (offset > 0 && text.IndexOf('\n') is var newline and >= 0)
        {
            // The read started mid-line; drop the partial first line.
            text = text[(newline + 1)..];
        }
        if (OpenAIUsageParser.LatestEvent(text) is { } found) return found;

        if (offset == 0 || size > fullReadLimit) return null;
        stream.Seek(0, SeekOrigin.Begin);
        return OpenAIUsageParser.LatestEvent(ReadToEnd(stream));
    }

    private static string ReadToEnd(Stream stream)
    {
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: false, leaveOpen: true);
        return reader.ReadToEnd();
    }
}
