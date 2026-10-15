using System.Text.Json;

namespace QuotaBar.Core;

public sealed record ThresholdEvent(AIProvider Provider, UsageWindow Window, int Threshold);

/// Decides when a usage alert is due, so each threshold fires once per quota
/// window. Same rules as the macOS ThresholdTracker; persisted between launches.
public sealed class ThresholdTracker
{
    public sealed class WindowState
    {
        public double LastPercentage { get; set; }
        public DateTimeOffset? ResetsAt { get; set; }
        public HashSet<int> Fired { get; set; } = [];
    }

    /// A fall this large without a known reset time is treated as a new window.
    private const double DropTolerance = 10;
    /// Reset times that move by less than this are the same window.
    private static readonly TimeSpan ResetTolerance = TimeSpan.FromSeconds(60);

    public Dictionary<string, WindowState> States { get; set; } = [];

    public List<ThresholdEvent> Evaluate(ProviderUsage usage, IReadOnlyCollection<int> thresholds, DateTimeOffset now)
    {
        var events = new List<ThresholdEvent>();
        foreach (var window in usage.Windows)
        {
            var key = $"{usage.Provider}.{window.Id}";
            var percentage = window.EffectivePercentage(now);
            var resetsAt = window.IsExpired(now) ? null : window.ResetsAt;
            if (!States.TryGetValue(key, out var state))
                state = States[key] = new WindowState { ResetsAt = resetsAt };

            if (IsNewWindow(state, percentage, resetsAt))
                state.Fired.Clear();

            // Announce only the highest threshold crossed, and mark the lower ones
            // as done so a jump from 70% to 96% produces one alert, not three.
            var crossed = thresholds.Where(t => percentage >= t).ToList();
            if (crossed.Count > 0 && !state.Fired.Contains(crossed.Max()))
                events.Add(new ThresholdEvent(usage.Provider, window, crossed.Max()));
            state.Fired.UnionWith(crossed);

            state.LastPercentage = percentage;
            state.ResetsAt = resetsAt;
        }
        return events;
    }

    private static bool IsNewWindow(WindowState previous, double percentage, DateTimeOffset? resetsAt)
    {
        // Usage only falls when a window rolls over. Requiring a fall also
        // protects against providers whose reset time slides while idle.
        if (percentage >= previous.LastPercentage) return false;
        if (previous.ResetsAt is { } old && resetsAt is { } next)
            return next - old > ResetTolerance;
        return previous.LastPercentage - percentage >= DropTolerance;
    }

    public static ThresholdTracker Load(AppPaths paths)
    {
        try
        {
            if (File.Exists(paths.NotificationStateFile))
                return JsonSerializer.Deserialize<ThresholdTracker>(File.ReadAllText(paths.NotificationStateFile)) ?? new();
        }
        catch (Exception exception) when (exception is IOException or JsonException)
        {
        }
        return new();
    }

    public void Save(AppPaths paths)
    {
        paths.EnsureSupportDirectory();
        AtomicFile.WriteAllText(paths.NotificationStateFile, JsonSerializer.Serialize(this));
    }
}
