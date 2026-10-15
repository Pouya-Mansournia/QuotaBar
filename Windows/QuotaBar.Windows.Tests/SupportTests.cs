using System.Diagnostics;
using System.Text.Json.Nodes;
using QuotaBar.Core;
using QuotaBar.Providers;

namespace QuotaBar.Windows.Tests;

public sealed class TempDirectory : IDisposable
{
    public string Path { get; } = Directory.CreateTempSubdirectory("quotabar-tests-").FullName;

    public void Dispose()
    {
        try
        {
            Directory.Delete(Path, recursive: true);
        }
        catch (IOException)
        {
        }
    }
}

public class ThresholdTrackerTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(1_760_000_000);

    private static ProviderUsage Usage(double percentage, DateTimeOffset? resetsAt) =>
        new(AIProvider.Claude, [new UsageWindow(UsageWindowType.FiveHour, percentage, resetsAt)], Now);

    [Fact]
    public void FiresHighestThresholdOncePerWindow()
    {
        var tracker = new ThresholdTracker();
        int[] thresholds = [80, 90, 95];
        var reset = Now.AddHours(2);

        Assert.Empty(tracker.Evaluate(Usage(70, reset), thresholds, Now));
        Assert.Equal(95, Assert.Single(tracker.Evaluate(Usage(96, reset), thresholds, Now)).Threshold);
        Assert.Empty(tracker.Evaluate(Usage(97, reset), thresholds, Now));

        // New window: usage falls and the reset time moves forward.
        Assert.Empty(tracker.Evaluate(Usage(5, reset.AddHours(5)), thresholds, Now));
        Assert.Equal(80, Assert.Single(tracker.Evaluate(Usage(81, reset.AddHours(5)), thresholds, Now)).Threshold);
    }

    [Fact]
    public void SlidingResetWithoutFallIsSameWindow()
    {
        var tracker = new ThresholdTracker();
        Assert.Single(tracker.Evaluate(Usage(85, Now.AddHours(1)), [80], Now));
        Assert.Empty(tracker.Evaluate(Usage(85, Now.AddHours(3)), [80], Now));
    }

    [Fact]
    public void ExpiredWindowCountsAsZero()
    {
        var window = new UsageWindow(UsageWindowType.FiveHour, 90, Now.AddMinutes(-1));
        Assert.Equal(0, window.EffectivePercentage(Now));
        Assert.Equal("Window reset · waiting for new data", Formatting.Reset(window, Now));
    }
}

public class BridgeTests
{
    private static AppPaths Paths(TempDirectory temp) =>
        new(Path.Combine(temp.Path, "support"), temp.Path, Path.Combine(temp.Path, ".codex"));

    [Fact]
    public void InstallKeepsOtherSettingsAndUninstallRestoresStatusLine()
    {
        using var temp = new TempDirectory();
        var paths = Paths(temp);
        Directory.CreateDirectory(paths.ClaudeDirectory);
        File.WriteAllText(paths.ClaudeSettingsFile, """{"theme":"dark","statusLine":{"type":"command","command":"echo mine"}}""");
        var bridge = new ClaudeStatusLineBridge(paths);

        bridge.Install();
        Assert.True(bridge.IsInstalled());
        var installed = JsonNode.Parse(File.ReadAllText(paths.ClaudeSettingsFile))!;
        Assert.Equal("dark", installed["theme"]!.GetValue<string>());
        Assert.Equal(bridge.Command, installed["statusLine"]!["command"]!.GetValue<string>());
        Assert.Equal("echo mine", File.ReadAllText(paths.BridgeChainFile));
        Assert.True(File.Exists(bridge.BackupFile));

        bridge.Uninstall();
        Assert.False(bridge.IsInstalled());
        var restored = JsonNode.Parse(File.ReadAllText(paths.ClaudeSettingsFile))!;
        Assert.Equal("echo mine", restored["statusLine"]!["command"]!.GetValue<string>());
    }

    [Fact]
    public void RefusesToEditInvalidSettings()
    {
        using var temp = new TempDirectory();
        var paths = Paths(temp);
        Directory.CreateDirectory(paths.ClaudeDirectory);
        File.WriteAllText(paths.ClaudeSettingsFile, "[1,2]");

        Assert.Throws<InvalidOperationException>(() => new ClaudeStatusLineBridge(paths).Install());
        Assert.Equal("[1,2]", File.ReadAllText(paths.ClaudeSettingsFile));
    }

    [Fact]
    public void ScriptCapturesRateLimitsAndPrintsStatusLine()
    {
        using var temp = new TempDirectory();
        var paths = Paths(temp);
        new ClaudeStatusLineBridge(paths).Install();

        var start = new ProcessStartInfo("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -File \"{paths.BridgeScriptFile}\"")
        {
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            UseShellExecute = false,
            StandardOutputEncoding = System.Text.Encoding.UTF8,
        };
        using var process = Process.Start(start)!;
        process.StandardInput.Write("""{"model":{"display_name":"Opus"},"rate_limits":{"five_hour":{"used_percentage":41.6,"resets_at":1760003600}}}""");
        process.StandardInput.Close();
        var output = process.StandardOutput.ReadToEnd();
        process.WaitForExit(30_000);

        Assert.Equal("Opus · 5h 42%", output.Trim());
        var usage = ClaudeUsageParser.ParseStatusLine(File.ReadAllText(paths.ClaudeSnapshotFile), DateTimeOffset.Now);
        Assert.Equal(41.6, usage.Windows[0].UsedPercentage);
    }
}

public class AccountSourceTests
{
    private sealed class StubCredentials(ClaudeCredential credential) : IClaudeCredentialProvider
    {
        public int Reads { get; private set; }
        public ClaudeCredential Read()
        {
            Reads++;
            return credential;
        }
    }

    private sealed class StubHandler(System.Net.HttpStatusCode status, string body) : HttpMessageHandler
    {
        public int Calls { get; private set; }
        public string? Authorization { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            Authorization = request.Headers.Authorization?.ToString();
            return Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent(body) });
        }
    }

    [Fact]
    public async Task FetchesOnceWithinMinimumInterval()
    {
        var handler = new StubHandler(System.Net.HttpStatusCode.OK, """{"five_hour":{"utilization":10}}""");
        var source = new ClaudeAccountUsageSource(new StubCredentials(new ClaudeCredential("abc", null)), handler);

        var first = await source.FetchAsync(CancellationToken.None);
        var second = await source.FetchAsync(CancellationToken.None);

        Assert.Same(first, second);
        Assert.Equal(1, handler.Calls);
        Assert.Equal("Bearer abc", handler.Authorization);
    }

    [Fact]
    public async Task UnauthorizedMeansSessionExpired()
    {
        var source = new ClaudeAccountUsageSource(
            new StubCredentials(new ClaudeCredential("abc", null)),
            new StubHandler(System.Net.HttpStatusCode.Unauthorized, ""));
        var error = await Assert.ThrowsAsync<ProviderException>(() => source.FetchAsync(CancellationToken.None));
        Assert.Equal(ProviderErrorKind.SessionExpired, error.Kind);
    }

    [Fact]
    public async Task ExpiredTokenIsNotSent()
    {
        var handler = new StubHandler(System.Net.HttpStatusCode.OK, "{}");
        var source = new ClaudeAccountUsageSource(new StubCredentials(new ClaudeCredential("abc", DateTimeOffset.Now.AddMinutes(-1))), handler);
        await Assert.ThrowsAsync<ProviderException>(() => source.FetchAsync(CancellationToken.None));
        Assert.Equal(0, handler.Calls);
    }
}
