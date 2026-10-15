using QuotaBar.Core;
using QuotaBar.Providers;

namespace QuotaBar.Windows.Tests;

public class ClaudeParserTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_760_000_000);

    [Fact]
    public void ParsesStatusLineWindows()
    {
        var usage = ClaudeUsageParser.ParseStatusLine(
            """{"rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1760003600},"seven_day":{"used_percentage":"12%","resets_at":"2025-10-12T10:00:00Z"}}}""",
            Now);

        Assert.Equal(2, usage.Windows.Count);
        Assert.Equal(UsageWindowType.FiveHour, usage.Windows[0].Type);
        Assert.Equal(42.5, usage.Windows[0].UsedPercentage);
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1_760_003_600), usage.Windows[0].ResetsAt);
        Assert.Equal(12, usage.Windows[1].UsedPercentage);
        Assert.Equal(Now, usage.UpdatedAt);
    }

    [Fact]
    public void StatusLineWithoutRateLimitsIsNoData()
    {
        var error = Assert.Throws<ProviderException>(() => ClaudeUsageParser.ParseStatusLine("""{"model":{}}""", Now));
        Assert.Equal(ProviderErrorKind.NoUsageData, error.Kind);
    }

    [Fact]
    public void ParsesAccountUsageObjectShape()
    {
        var usage = ClaudeUsageParser.ParseAccountUsage(
            """{"five_hour":{"utilization":33,"resets_at":"2025-10-09T15:00:00.123Z"},"seven_day":{"utilization":150},"seven_day_opus":{"utilization":80}}""",
            Now);

        Assert.Equal(2, usage.Windows.Count);
        Assert.Equal(33, usage.Windows[0].UsedPercentage);
        Assert.NotNull(usage.Windows[0].ResetsAt);
        Assert.Equal(100, usage.Windows[1].UsedPercentage); // clamped
    }

    [Fact]
    public void ParsesAccountUsageListShapeAndSkipsModelLimits()
    {
        var usage = ClaudeUsageParser.ParseAccountUsage(
            """{"limits":[{"type":"weekly_opus","utilization":90},{"type":"session","utilization":"20"},{"type":"weekly","percent":55}]}""",
            Now);

        Assert.Equal([UsageWindowType.FiveHour, UsageWindowType.Weekly], usage.Windows.Select(w => w.Type));
        Assert.Equal(55, usage.Windows[1].UsedPercentage);
    }

    [Fact]
    public void UnknownAccountShapeReportsKeysOnly()
    {
        var error = Assert.Throws<ProviderException>(() => ClaudeUsageParser.ParseAccountUsage("""{"secret":"abc","other":1}""", Now));
        Assert.Equal(ProviderErrorKind.UnsupportedResponse, error.Kind);
        Assert.Contains("other, secret", error.Detail);
        Assert.DoesNotContain("abc", error.Detail);
    }

    [Fact]
    public void ParsesCredentialWithoutLeakingToken()
    {
        var credential = ClaudeCredentialsFile.Parse("""{"claudeAiOauth":{"accessToken":"tok","expiresAt":1760000000000}}""");
        Assert.Equal("tok", credential.AccessToken);
        Assert.Equal(DateTimeOffset.FromUnixTimeSeconds(1_760_000_000), credential.ExpiresAt);

        var error = Assert.Throws<ProviderException>(() => ClaudeCredentialsFile.Parse("""{"other":"tok-secret"}"""));
        Assert.DoesNotContain("tok-secret", error.Message);
    }
}

public class CodexParserTests
{
    private const string Line =
        """{"timestamp":"2025-10-09T12:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":30,"window_minutes":300,"resets_at":1760010000},"secondary":{"used_percent":"61.5","window_minutes":10080,"resets_in_seconds":3600},"plan_type":"plus"}}}""";

    [Fact]
    public void ReadsLatestEventFromJsonl()
    {
        var older = Line.Replace("\"used_percent\":30", "\"used_percent\":5");
        var jsonl = string.Join("\n", older, """{"payload":{"type":"message","text":"hi"}}""", "not json \"rate_limits\"", Line, "");
        var limitEvent = OpenAIUsageParser.LatestEvent(jsonl);

        Assert.NotNull(limitEvent);
        var usage = OpenAIUsageParser.Usage(limitEvent!, DateTimeOffset.Now);
        Assert.Equal(30, usage.Windows[0].UsedPercentage);
        Assert.Equal(UsageWindowType.Weekly, usage.Windows[1].Type);
        Assert.Equal(61.5, usage.Windows[1].UsedPercentage);
        Assert.Equal(DateTimeOffset.Parse("2025-10-09T13:00:00Z"), usage.Windows[1].ResetsAt);
        Assert.Equal("Plus", usage.PlanName);
    }

    [Fact]
    public void PrefersGeneralLimitOverModelSpecific()
    {
        var model = Line.Replace("\"plan_type\"", "\"limit_id\":\"gpt-5-codex\",\"plan_type\"").Replace("\"used_percent\":30", "\"used_percent\":99");
        var general = Line.Replace("\"plan_type\"", "\"limit_id\":\"codex\",\"plan_type\"");
        var limitEvent = OpenAIUsageParser.LatestEvent(general + "\n" + model);

        Assert.Equal(30, OpenAIUsageParser.Usage(limitEvent!, DateTimeOffset.Now).Windows[0].UsedPercentage);
    }

    [Theory]
    [InlineData(300, UsageWindowType.FiveHour, null)]
    [InlineData(10080, UsageWindowType.Weekly, null)]
    [InlineData(43200, UsageWindowType.Monthly, null)]
    [InlineData(30, UsageWindowType.Custom, "30m")]
    [InlineData(120, UsageWindowType.Custom, "2h")]
    [InlineData(4320, UsageWindowType.Custom, "3d")]
    public void MapsWindowLengths(double minutes, UsageWindowType type, string? label)
    {
        Assert.Equal((type, label), OpenAIUsageParser.WindowType(minutes));
    }

    [Fact]
    public async Task ProviderReadsNewestRolloutFromDisk()
    {
        using var temp = new TempDirectory();
        var day = Directory.CreateDirectory(Path.Combine(temp.Path, ".codex", "sessions", "2025", "10", "09")).FullName;
        File.WriteAllText(Path.Combine(day, "rollout-a.jsonl"), new string('x', 400) + "\n" + Line + "\n");
        var paths = new AppPaths(Path.Combine(temp.Path, "support"), temp.Path, Path.Combine(temp.Path, ".codex"));

        var usage = await new OpenAIUsageProvider(paths) { TailBytes = 100 }.FetchUsageAsync(CancellationToken.None);
        Assert.Equal(30, usage.Windows[0].UsedPercentage);
    }
}
