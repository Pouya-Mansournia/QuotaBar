using System.Text.Json;
using System.Text.Json.Serialization;

namespace QuotaBar.Core;

public enum ClaudeSource { Account, StatusLine }

public enum TrayDisplay { Highest, Claude, Codex }

public sealed class AppSettings
{
    public bool HasCompletedSetup { get; set; }
    public bool ClaudeEnabled { get; set; } = true;
    public bool CodexEnabled { get; set; } = true;
    /// On Windows the account source needs no consent dialog, so it is the default.
    public ClaudeSource ClaudeSource { get; set; } = ClaudeSource.Account;
    public TrayDisplay TrayDisplay { get; set; } = TrayDisplay.Highest;
    public int RefreshSeconds { get; set; } = 120;
    public bool NotificationsEnabled { get; set; } = true;
    public List<int> Thresholds { get; set; } = [80, 90, 95];
    public bool ShowWidget { get; set; } = true;
    public bool WidgetOnTop { get; set; } = true;
    public int? WidgetX { get; set; }
    public int? WidgetY { get; set; }

    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static AppSettings Load(AppPaths paths)
    {
        try
        {
            if (File.Exists(paths.SettingsFile))
                return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(paths.SettingsFile), Options) ?? new AppSettings();
        }
        catch (Exception exception) when (exception is IOException or JsonException or UnauthorizedAccessException)
        {
            // A damaged settings file falls back to defaults.
        }
        return new AppSettings();
    }

    public void Save(AppPaths paths)
    {
        paths.EnsureSupportDirectory();
        AtomicFile.WriteAllText(paths.SettingsFile, JsonSerializer.Serialize(this, Options));
    }
}

public static class AtomicFile
{
    public static void WriteAllText(string path, string contents)
    {
        var temp = path + ".tmp";
        File.WriteAllText(temp, contents);
        File.Move(temp, path, overwrite: true);
    }
}
