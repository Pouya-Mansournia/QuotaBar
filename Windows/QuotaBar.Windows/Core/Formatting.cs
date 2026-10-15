namespace QuotaBar.Core;

public static class Formatting
{
    /// "2h 14m", "3d 4h", "45s".
    public static string Duration(TimeSpan span)
    {
        if (span < TimeSpan.Zero) span = TimeSpan.Zero;
        if (span.TotalDays >= 1) return $"{(int)span.TotalDays}d {span.Hours}h";
        if (span.TotalHours >= 1) return $"{(int)span.TotalHours}h {span.Minutes}m";
        if (span.TotalMinutes >= 1) return $"{(int)span.TotalMinutes}m";
        return $"{(int)span.TotalSeconds}s";
    }

    public static string Reset(UsageWindow window, DateTimeOffset now)
    {
        if (window.IsExpired(now)) return "Window reset · waiting for new data";
        if (window.ResetsAt is not { } reset) return "Reset time unavailable";
        return $"Resets in {Duration(reset - now)}";
    }

    public static string Ago(DateTimeOffset date, DateTimeOffset now)
    {
        var span = now - date;
        return span < TimeSpan.FromMinutes(1) ? "just now" : $"{Duration(span)} ago";
    }
}
