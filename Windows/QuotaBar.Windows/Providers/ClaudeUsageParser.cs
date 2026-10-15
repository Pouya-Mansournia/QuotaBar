using System.Text.Json;
using QuotaBar.Core;

namespace QuotaBar.Providers;

/// Turns Claude data into usage windows. Pure; no I/O.
public static class ClaudeUsageParser
{
    /// Status line JSON as captured by the bridge script.
    public static ProviderUsage ParseStatusLine(string json, DateTimeOffset capturedAt)
    {
        JsonElement root;
        try
        {
            using var document = JsonDocument.Parse(json);
            root = document.RootElement.Clone();
        }
        catch (JsonException)
        {
            throw ProviderException.Unsupported("Claude status line JSON could not be decoded");
        }

        // Claude Code only sends rate_limits to Pro/Max subscribers, and only
        // after the first API response of a session.
        if (Lenient.Object(root, "rate_limits") is not { } limits)
            throw ProviderException.NoUsageData("Claude Code has not reported usage limits");

        var windows = new List<UsageWindow>();
        AddStatusWindow(windows, Lenient.Object(limits, "five_hour"), UsageWindowType.FiveHour);
        AddStatusWindow(windows, Lenient.Object(limits, "seven_day"), UsageWindowType.Weekly);
        AddStatusWindow(windows, Lenient.Object(limits, "spend_limit"), UsageWindowType.ApiBudget);

        if (windows.Count == 0)
            throw ProviderException.NoUsageData("Claude Code has not reported usage limits");
        return new ProviderUsage(AIProvider.Claude, windows, capturedAt);
    }

    private static void AddStatusWindow(List<UsageWindow> windows, JsonElement? raw, UsageWindowType type)
    {
        if (raw is not { } element || UsageMath.NormalizedPercentage(Lenient.Number(element, "used_percentage")) is not { } percentage)
            return;
        windows.Add(new UsageWindow(type, percentage, Lenient.Date(element, "resets_at"))
        {
            EstimatedCost = type == UsageWindowType.ApiBudget ? Lenient.Number(element, "used_usd") : null,
        });
    }

    private static readonly string[] PercentageKeys = ["utilization", "used_percentage", "used_percent", "percent", "percentage"];
    private static readonly string[] ResetKeys = ["resets_at", "reset_at", "resetsAt", "resets"];
    private static readonly string[] NameKeys = ["type", "id", "name", "window", "key", "label"];

    /// Parses the Anthropic account usage endpoint.
    ///
    /// Known shapes: `{"five_hour":{"utilization":33,"resets_at":"…"},"seven_day":{…}}`
    /// and a newer `{"limits":[{…}]}` list. Model-specific weekly limits are ignored.
    public static ProviderUsage ParseAccountUsage(string json, DateTimeOffset fetchedAt)
    {
        JsonElement root;
        try
        {
            using var document = JsonDocument.Parse(json);
            root = document.RootElement.Clone();
        }
        catch (JsonException)
        {
            throw ProviderException.Unsupported("Account usage response is not JSON");
        }
        if (root.ValueKind != JsonValueKind.Object)
            throw ProviderException.Unsupported("Account usage response is not a JSON object");

        var windows = new List<UsageWindow>();
        void Add(JsonElement? raw, UsageWindowType type)
        {
            if (windows.Any(w => w.Type == type) || raw is not { ValueKind: JsonValueKind.Object } element) return;
            if (UsageMath.NormalizedPercentage(Lenient.Number(element, PercentageKeys)) is not { } percentage) return;
            windows.Add(new UsageWindow(type, percentage, Lenient.Date(element, ResetKeys)));
        }

        Add(Lenient.Property(root, "five_hour"), UsageWindowType.FiveHour);
        Add(Lenient.Property(root, "seven_day"), UsageWindowType.Weekly);

        if (Lenient.Property(root, "limits") is { ValueKind: JsonValueKind.Array } limits)
        {
            foreach (var item in limits.EnumerateArray())
            {
                var name = string.Join(" ", NameKeys.Select(key => Lenient.String(item, key)).OfType<string>()).ToLowerInvariant();
                // Per-model limits are separate quotas, not the overall weekly one.
                if (name.Length == 0 || new[] { "opus", "sonnet", "haiku", "oauth" }.Any(name.Contains)) continue;
                if (new[] { "five", "5h", "5_h", "session" }.Any(name.Contains))
                    Add(item, UsageWindowType.FiveHour);
                else if (new[] { "seven", "week", "7d", "7_d" }.Any(name.Contains))
                    Add(item, UsageWindowType.Weekly);
            }
        }

        if (windows.Count == 0)
        {
            if (new[] { "five_hour", "seven_day", "limits" }.Any(key => root.TryGetProperty(key, out _)))
                throw ProviderException.NoUsageData("No active Claude usage window reported");
            // Key names only, never values, so the shape can be diagnosed.
            var keys = string.Join(", ", root.EnumerateObject().Select(p => p.Name).Order());
            throw ProviderException.Unsupported($"Unrecognised account usage fields: {keys}");
        }
        return new ProviderUsage(AIProvider.Claude, windows, fetchedAt);
    }
}
