using System.Text.Json;
using System.Text.Json.Nodes;
using QuotaBar.Core;

namespace QuotaBar.Providers;

/// Installs and removes the status line script that lets QuotaBar see the
/// rate-limit data Claude Code already computes.
///
/// Claude Code pipes a JSON document to its configured `statusLine` command.
/// The bridge script stores that document's `rate_limits` object in QuotaBar's
/// data directory and then runs whatever status line was configured before.
///
/// Installing edits `~/.claude/settings.json`; it only happens from an explicit
/// button, and the previous value is saved for uninstall.
public sealed class ClaudeStatusLineBridge(AppPaths paths)
{
    /// The value written to `statusLine.command`. Claude Code on Windows runs it
    /// through Git Bash, so the path uses forward slashes.
    public string Command =>
        $"powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"{paths.BridgeScriptFile.Replace('\\', '/')}\"";

    public string BackupFile => paths.ClaudeSettingsFile + ".quotabar-backup";

    public bool IsInstalled()
    {
        if (!File.Exists(paths.BridgeScriptFile)) return false;
        try
        {
            return LoadSettings()["statusLine"]?["command"]?.GetValue<string>() == Command;
        }
        catch (Exception exception) when (exception is IOException or InvalidOperationException or JsonException)
        {
            return false;
        }
    }

    public void Install()
    {
        paths.EnsureSupportDirectory();
        // Windows PowerShell reads BOM-less scripts as ANSI; the BOM keeps "·" intact.
        File.WriteAllText(paths.BridgeScriptFile, Script, new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: true));

        var settings = LoadSettings();
        var existing = settings["statusLine"] as JsonObject;
        if (existing?["command"]?.GetValue<string>() == Command) return;

        // Remember what was there so uninstall can put it back, and so the
        // script can keep rendering the user's own status line.
        File.Delete(paths.BridgeOriginalFile);
        File.Delete(paths.BridgeChainFile);
        if (existing is not null)
        {
            File.WriteAllText(paths.BridgeOriginalFile, existing.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            if (existing["type"]?.GetValue<string>() == "command" &&
                existing["command"]?.GetValue<string>() is { } previous && !string.IsNullOrWhiteSpace(previous))
                File.WriteAllText(paths.BridgeChainFile, previous);
        }

        if (File.Exists(paths.ClaudeSettingsFile))
            File.Copy(paths.ClaudeSettingsFile, BackupFile, overwrite: true);

        var statusLine = existing is null ? new JsonObject() : (JsonObject)existing.DeepClone();
        statusLine["type"] = "command";
        statusLine["command"] = Command;
        settings["statusLine"] = statusLine;
        SaveSettings(settings);
    }

    public void Uninstall()
    {
        var settings = LoadSettings();
        if (settings["statusLine"]?["command"]?.GetValue<string>() == Command)
        {
            JsonNode? original = null;
            try
            {
                if (File.Exists(paths.BridgeOriginalFile))
                    original = JsonNode.Parse(File.ReadAllText(paths.BridgeOriginalFile)) as JsonObject;
            }
            catch (JsonException)
            {
            }
            if (original is null) settings.Remove("statusLine");
            else settings["statusLine"] = original;
            SaveSettings(settings);
        }
        foreach (var file in new[] { paths.BridgeScriptFile, paths.BridgeChainFile, paths.BridgeOriginalFile, paths.ClaudeSnapshotFile })
            File.Delete(file);
    }

    private JsonObject LoadSettings()
    {
        if (!File.Exists(paths.ClaudeSettingsFile)) return [];
        var text = File.ReadAllText(paths.ClaudeSettingsFile);
        if (string.IsNullOrWhiteSpace(text)) return [];
        try
        {
            if (JsonNode.Parse(text) is JsonObject settings) return settings;
        }
        catch (JsonException)
        {
        }
        throw new InvalidOperationException("Claude Code's settings.json is not a JSON object, so QuotaBar left it untouched.");
    }

    private void SaveSettings(JsonObject settings)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(paths.ClaudeSettingsFile)!);
        var options = new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
        AtomicFile.WriteAllText(paths.ClaudeSettingsFile, settings.ToJsonString(options) + "\n");
    }

    /// Windows PowerShell 5.1, which ships with Windows.
    public const string Script = """
        # QuotaBar status line bridge. Managed by QuotaBar; remove it from
        # QuotaBar > Settings rather than editing it.
        #
        # Claude Code pipes its status JSON to this script. The script keeps only the
        # rate_limits object, in a file next to itself, for QuotaBar to read. It makes
        # no network requests and stores nothing else from the payload.
        $ErrorActionPreference = 'SilentlyContinue'
        [Console]::InputEncoding = [Text.Encoding]::UTF8
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        $dir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $raw = [Console]::In.ReadToEnd()
        $data = $null
        try { $data = $raw | ConvertFrom-Json } catch { }

        # rate_limits is absent until the first API response of a session; keep the
        # previous snapshot in that case.
        if ($data -and $data.rate_limits) {
          $tmp = Join-Path $dir (".snapshot.$PID.tmp")
          $json = @{ rate_limits = $data.rate_limits } | ConvertTo-Json -Depth 10 -Compress
          [IO.File]::WriteAllText($tmp, $json)
          Move-Item -Force $tmp (Join-Path $dir 'claude-statusline.json')
        }

        $chain = Join-Path $dir 'statusline-chain-command'
        if ((Test-Path $chain) -and (Get-Item $chain).Length -gt 0) {
          # Hand the untouched payload to the status line that was configured before.
          $command = [IO.File]::ReadAllText($chain)
          if (Get-Command bash -ErrorAction SilentlyContinue) { $raw | bash -c $command }
          else { $raw | cmd.exe /c $command }
        } else {
          $line = 'Claude'
          if ($data -and $data.model -and $data.model.display_name) { $line = $data.model.display_name }
          $limits = if ($data) { $data.rate_limits } else { $null }
          if ($limits -and $limits.five_hour -and $null -ne $limits.five_hour.used_percentage) {
            $line += ' · 5h ' + [math]::Round([double]$limits.five_hour.used_percentage) + '%'
          }
          if ($limits -and $limits.seven_day -and $null -ne $limits.seven_day.used_percentage) {
            $line += ' · 7d ' + [math]::Round([double]$limits.seven_day.used_percentage) + '%'
          }
          Write-Output $line
        }

        """;
}
