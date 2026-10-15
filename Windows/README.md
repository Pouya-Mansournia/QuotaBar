# QuotaBar for Windows

A notification-area (system tray) app and desktop widget that shows how much of your Claude and Codex usage limits you have left. It is a C# / WinForms port of the macOS app and reads the same data sources.

- Tray icon with a gauge ring and the highest usage percentage; hover for a summary
- Click the icon for the full panel: 5-hour and weekly usage, reset countdowns, reading age
- **Desktop widget**: a small floating card with every window as a bar. Drag it anywhere (the position is remembered), double-click for the full panel, right-click for the menu. Turn it on or off from the tray menu, the panel's **Widget** button, or Settings
- Notifications at 80 / 90 / 95 % (configurable), once per quota window
- Follows the Windows light/dark setting and display scaling
- Launch at login (per-user, no admin rights)

## Requirements

- Windows 10 or 11
- [.NET 8 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) to build; the .NET 8 Desktop Runtime to run a framework-dependent build

## Build and run

```powershell
cd Windows
dotnet test                                    # unit tests
dotnet run --project QuotaBar.Windows          # build Debug and launch
dotnet publish QuotaBar.Windows -c Release -r win-x64 --self-contained -p:PublishSingleFile=true -o publish
```

The last command produces a single `publish\QuotaBar.exe` that runs without .NET installed. Copy it anywhere, run it, and turn on **Settings → Launch at login**.

## Data sources

**Claude, account source (default).** On Windows, Claude Code keeps its sign-in in `%USERPROFILE%\.claude\.credentials.json` instead of a keychain, so no permission dialog is needed. QuotaBar reads the access token from that file and sends one GET request to `https://api.anthropic.com/api/oauth/usage`, at most every two minutes. The token goes nowhere else, is never written or logged, and is never refreshed by QuotaBar (Claude Code renews it itself). Works with the VS Code extension too. The endpoint is not officially documented, so an unrecognised response is shown as "Unsupported provider response", never as a guess.

**Claude, status line bridge (no network).** **Settings → Status line bridge → Install** writes `%APPDATA%\QuotaBar\quotabar-statusline.ps1` and registers it as Claude Code's `statusLine` command in `~/.claude/settings.json` (a backup is written next to it). The script saves only the `rate_limits` object, then runs your previous status line if you had one. **Remove** restores the previous value. Values update only while Claude Code runs in a terminal.

**Codex.** Reads the most recent rate-limit record from the Codex CLI session logs (`%USERPROFILE%\.codex\sessions\**\rollout-*.jsonl`, or `%CODEX_HOME%`). No credentials, no network.

QuotaBar's own files (settings, alert state, bridge snapshot) live in `%APPDATA%\QuotaBar`.

## Layout

```text
Windows/
├── QuotaBar.Windows/
│   ├── Core/        models, lenient JSON helpers, settings, paths, store, alert tracker
│   ├── Providers/   Claude (parser, credentials file, account endpoint, bridge), Codex
│   └── App/         tray application, panel, widget, settings window, icon rendering
└── QuotaBar.Windows.Tests/   xUnit tests (parsers, alerts, bridge script, account source)
```

The parsing rules and alert rules match the macOS app; see [ARCHITECTURE.md](../ARCHITECTURE.md).
