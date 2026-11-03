using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace QuotaBar.App;

/// <summary>Installs a newer, published Windows release for per-user installations.</summary>
internal sealed class ReleaseUpdater : IDisposable
{
    private const string LatestRelease = "https://api.github.com/repos/Pouya-Mansournia/QuotaBar/releases/latest";
    private const string AssetPrefix = "https://github.com/Pouya-Mansournia/QuotaBar/releases/download/";
    private readonly HttpClient _client = new() { Timeout = TimeSpan.FromMinutes(5) };
    private readonly System.Windows.Forms.Timer _timer = new() { Interval = 6 * 60 * 60 * 1000 };
    private readonly string _installedExe = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "QuotaBar", "QuotaBar.exe");
    private int _checking;

    public event Action? InstallerStarted;

    public ReleaseUpdater()
    {
        _client.DefaultRequestHeaders.UserAgent.ParseAdd("QuotaBar/" + AppInfo.Version);
        _client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");
        _timer.Tick += (_, _) => _ = CheckAsync();
        _timer.Start();
        _ = CheckAsync();
    }

    internal static Version? ParseReleaseVersion(string tag)
    {
        var value = tag.StartsWith("Windows-v", StringComparison.OrdinalIgnoreCase)
            ? tag[9..]
            : tag.TrimStart('v', 'V');
        return Version.TryParse(value, out var version) && version.Build >= 0 ? version : null;
    }

    private async Task CheckAsync()
    {
        // Portable copies have no Inno Setup installation to upgrade.
        if (!string.Equals(Environment.ProcessPath, _installedExe, StringComparison.OrdinalIgnoreCase)
            || Interlocked.Exchange(ref _checking, 1) != 0) return;

        string? download = null;
        try
        {
            using var response = await _client.GetAsync(LatestRelease);
            response.EnsureSuccessStatusCode();
            using var release = JsonDocument.Parse(await response.Content.ReadAsStreamAsync());
            var root = release.RootElement;
            var version = ParseReleaseVersion(root.GetProperty("tag_name").GetString() ?? "");
            if (version is null || !Version.TryParse(AppInfo.Version, out var current) || version <= current) return;

            var expectedName = $"QuotaBar-Setup-{version.ToString(3)}.exe";
            foreach (var asset in root.GetProperty("assets").EnumerateArray())
            {
                if (asset.GetProperty("name").GetString() != expectedName) continue;
                var uri = asset.GetProperty("browser_download_url").GetString();
                var digest = asset.TryGetProperty("digest", out var hash) ? hash.GetString() : null;
                var size = asset.GetProperty("size").GetInt64();
                if (uri is null || !uri.StartsWith(AssetPrefix, StringComparison.Ordinal)
                    || digest is null || !digest.StartsWith("sha256:", StringComparison.Ordinal)
                    || size is <= 0 or > 250_000_000) return;

                download = Path.Combine(Path.GetTempPath(), $"QuotaBar-update-{Guid.NewGuid():N}.exe");
                using var fileResponse = await _client.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead);
                fileResponse.EnsureSuccessStatusCode();
                await using (var output = File.Create(download))
                    await fileResponse.Content.CopyToAsync(output);
                string actual;
                await using (var downloadedFile = File.OpenRead(download))
                {
                    if (downloadedFile.Length != size) return;
                    actual = Convert.ToHexString(await SHA256.HashDataAsync(downloadedFile));
                }
                if (!string.Equals(actual, digest[7..], StringComparison.OrdinalIgnoreCase)) return;

                Process.Start(new ProcessStartInfo(download,
                    "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS")
                { UseShellExecute = true });
                download = null; // The installer owns this file while it runs.
                InstallerStarted?.Invoke();
                return;
            }
        }
        catch (Exception error)
        {
            Debug.WriteLine($"QuotaBar update check failed: {error.Message}");
        }
        finally
        {
            if (download is not null) try { File.Delete(download); } catch (IOException) { }
            Interlocked.Exchange(ref _checking, 0);
        }
    }

    public void Dispose()
    {
        _timer.Dispose();
        _client.Dispose();
    }
}
