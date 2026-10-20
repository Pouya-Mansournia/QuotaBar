# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Windows 1.0.2 (2026-10-20)

### Added
- A **Reconnect** button on a provider card when its sign-in has expired or is missing. It opens a console running `claude /login` (or `codex login`) and refreshes usage when the console closes.

## Windows 1.0.1 (2026-10-15)

### Added
- Settings shows the version, "Engineered by P.Mansournia" and a link to the GitHub repository.
- The credit line in the panel opens the GitHub repository.

## Windows 1.0.0 (2026-10-15)

### Added
- Windows version (C# / .NET 8, WinForms) under `Windows/`: notification-area icon with a usage gauge, flyout panel, and a draggable, always-visible desktop widget.
- Claude usage from the Anthropic account endpoint using Claude Code's `~/.claude/.credentials.json`, or an optional PowerShell status line bridge.
- Codex usage from local session logs.
- Threshold notifications, launch at login, light/dark and DPI-aware rendering.
- Per-user installer (`QuotaBar-Setup-1.0.0.exe`, Inno Setup) and xUnit tests.

## macOS 1.0.2

### Added
- Guided Claude Code install in the setup window, and a credit line.

## macOS 1.0.1

### Added
- First-run setup window and one-click Claude connect.

## macOS 1.0.0

### Added
- Native macOS menu bar app for Claude and Codex usage: 5-hour and weekly windows, reset countdowns, notifications, usage history.
