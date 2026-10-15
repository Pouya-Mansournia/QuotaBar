namespace QuotaBar.Core;

public enum AIProvider { Claude, Codex }

public static class AIProviderInfo
{
    public static string DisplayName(this AIProvider provider) => provider == AIProvider.Claude ? "Claude" : "Codex";
    public static string ShortCode(this AIProvider provider) => provider == AIProvider.Claude ? "C" : "O";
}

public enum UsageWindowType { FiveHour, Daily, Weekly, Monthly, ApiBudget, Custom }

public sealed record UsageWindow(UsageWindowType Type, double UsedPercentage, DateTimeOffset? ResetsAt, string? Label = null)
{
    public double? EstimatedCost { get; init; }

    public string Id => Label is null ? Type.ToString() : $"{Type}.{Label}";

    public string Title => Type switch
    {
        UsageWindowType.FiveHour => "5-hour",
        UsageWindowType.Daily => "Daily",
        UsageWindowType.Weekly => "Weekly",
        UsageWindowType.Monthly => "Monthly",
        UsageWindowType.ApiBudget => "Spend Limit",
        _ => Label ?? "Limit",
    };

    public bool IsExpired(DateTimeOffset now) => ResetsAt is { } reset && reset <= now;

    /// A window whose reset time has passed belongs to an ended quota period.
    public double EffectivePercentage(DateTimeOffset now) => IsExpired(now) ? 0 : UsedPercentage;
}

public sealed record ProviderUsage(AIProvider Provider, IReadOnlyList<UsageWindow> Windows, DateTimeOffset UpdatedAt, string? PlanName = null)
{
    public double HighestPercentage(DateTimeOffset now) =>
        Windows.Count == 0 ? 0 : Windows.Max(w => w.EffectivePercentage(now));
}

public enum ProviderErrorKind
{
    CliNotInstalled, NotConfigured, AuthenticationRequired, SessionExpired, NoUsageData,
    PermissionDenied, NetworkUnavailable, UnsupportedResponse, TimedOut, Unknown,
}

/// Providers report facts or throw this. The message is user-facing and never
/// contains a credential or a stack trace.
public sealed class ProviderException : Exception
{
    public ProviderErrorKind Kind { get; }
    public string Detail { get; }

    public ProviderException(ProviderErrorKind kind, string detail = "") : base(BuildMessage(kind, detail))
    {
        Kind = kind;
        Detail = detail;
    }

    public static ProviderException CliNotInstalled(string tool) => new(ProviderErrorKind.CliNotInstalled, tool);
    public static ProviderException NotConfigured(string hint) => new(ProviderErrorKind.NotConfigured, hint);
    public static ProviderException AuthenticationRequired(string tool) => new(ProviderErrorKind.AuthenticationRequired, tool);
    public static ProviderException SessionExpired(string tool) => new(ProviderErrorKind.SessionExpired, tool);
    public static ProviderException NoUsageData(string hint) => new(ProviderErrorKind.NoUsageData, hint);
    public static ProviderException Unsupported(string detail) => new(ProviderErrorKind.UnsupportedResponse, detail);

    private static string BuildMessage(ProviderErrorKind kind, string detail) => kind switch
    {
        ProviderErrorKind.CliNotInstalled => $"{detail} not installed",
        ProviderErrorKind.NotConfigured => detail,
        ProviderErrorKind.AuthenticationRequired => $"{detail} authentication unavailable",
        ProviderErrorKind.SessionExpired => $"{detail} sign-in expired — open {detail} to renew it",
        ProviderErrorKind.NoUsageData => detail,
        ProviderErrorKind.PermissionDenied => "Permission denied",
        ProviderErrorKind.NetworkUnavailable => "Network unavailable",
        ProviderErrorKind.UnsupportedResponse => "Unsupported provider response",
        ProviderErrorKind.TimedOut => "Unable to read usage (timed out)",
        _ => "Unable to read usage",
    };
}

public interface IUsageProvider
{
    AIProvider Provider { get; }
    Task<ProviderUsage> FetchUsageAsync(CancellationToken cancellationToken);
}

public static class UsageMath
{
    public static double? NormalizedPercentage(double? raw) =>
        raw is { } value && double.IsFinite(value) ? Math.Clamp(value, 0, 100) : null;

    /// Rounds down so a threshold is never shown as reached before it is.
    public static int DisplayPercent(double percentage) => (int)Math.Floor(percentage);
}
