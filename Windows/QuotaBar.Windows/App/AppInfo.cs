using System.Diagnostics;
using System.Reflection;

namespace QuotaBar.App;

public static class AppInfo
{
    public const string RepositoryUrl = "https://github.com/Pouya-Mansournia/QuotaBar";

    public static string Version =>
        Assembly.GetExecutingAssembly().GetName().Version is { } version ? $"{version.Major}.{version.Minor}.{version.Build}" : "";

    public static void Open(string url) => Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
}
