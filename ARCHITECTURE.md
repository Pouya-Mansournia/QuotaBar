# Architecture

QuotaBar is a SwiftUI menu bar app (`MenuBarExtra`, macOS 14+) written in Swift 6 language mode with no third-party dependencies.

## Data flow

```text
Data source                status line snapshot / Codex session logs /
                           Anthropic account endpoint (opt-in)
        ↓
UsageProvider              ClaudeUsageProvider, OpenAIUsageProvider   (I/O)
        ↓                  ClaudeUsageParser,  OpenAIUsageParser      (pure)
UsageService               runs providers concurrently, maps errors to ProviderError
        ↓
UsageStore                 @MainActor @Observable: snapshots, stale policy,
        ↓                  cache, history, alert evaluation
SwiftUI views              menu bar label, menu, Settings, History
```

`AppEnvironment` is the composition root. It builds this graph once, owns the refresh schedule, and is passed to views through the SwiftUI environment. There are no singletons apart from `AppLog`, which wraps the unified log.

## Layout

```text
QuotaBar/
├── App/            QuotaBarApp (scenes), AppDelegate, AppEnvironment
├── Core/
│   ├── Models/         AIProvider, UsageWindow, ProviderUsage, ProviderSnapshot,
│   │                   ProviderError, AppSettings, lenient decoding helpers
│   ├── Services/       UsageProvider protocol, UsageService, UsageStore,
│   │                   RefreshScheduler, ResetFormatter, LaunchAtLogin, AppLog
│   ├── Persistence/    AppPaths, JSONFileStore (cache), HistoryStore
│   ├── Notifications/  ThresholdTracker (pure), NotificationManager
│   └── Security/       Redactor, KeychainReader
├── Providers/
│   ├── Claude/         provider, parser, models, status line bridge,
│   │                   account usage source
│   ├── OpenAI/         provider, parser, models, session locator
│   └── Mock/           Debug-only sample data
├── CLI/            CLILocator, CLIExecutor
├── Features/       MenuBar, Settings, History, Diagnostics
└── Resources/      asset catalog (app icon)
QuotaBarTests/      unit tests, hosted by the app
Scripts/            generate-icon.swift
```

The Xcode project uses file-system-synchronized groups, so files added to these folders are picked up without editing the project file. `Info.plist` is generated from build settings (`LSUIElement` hides the Dock icon).

## Key decisions

**Providers report facts or throw.** `fetchUsage()` returns a `ProviderUsage` or throws a `ProviderError`. There is no partial or placeholder result. `UsageStore` keeps the previous reading when a refresh fails and marks it stale. A provider with no reading at all is shown as Unavailable.

**Measured time is separate from read time.** Both sources are files written by another tool, so `ProviderUsage.updatedAt` is when the tool measured the value, not when QuotaBar read it. The UI shows that age. A window whose `resetsAt` has passed is displayed as reset (0 %, "waiting for new data"), because the stored percentage belongs to a quota period that has ended.

**Parsing is isolated and lenient.** Parsers are pure functions over `Data`. Numbers may arrive as strings, timestamps as epoch seconds, milliseconds or ISO 8601, and a malformed field is treated as absent instead of failing the document. Unknown fields are ignored.

**Alerts fire once per window.** `ThresholdTracker` is a persisted value type. It announces only the highest newly crossed threshold. It treats a window as new when usage falls and the reset time moves forward, or when usage falls by 10 points with no reset time. Requiring a fall avoids repeat alerts from providers whose reset time slides while idle.

**One opt-in path for credentials and network.** `ClaudeAccountUsageSource` is an actor that owns the in-memory token, the two-minute request floor and the back-off after a declined Keychain prompt. It takes a `ClaudeCredentialProviding` and an `HTTPTransport`, so tests run it without a Keychain or a network. It never refreshes the token.

**Low idle cost.** `RefreshScheduler` is one sleeping task with tolerance, not a repeating timer. Reset countdowns are computed from the stored reset time in a `TimelineView` that ticks every 15 seconds. The Codex provider reads the last 256 KB of the newest session files and falls back to a full read only when that tail has no reading.

**History is append-only JSON Lines.** A sample is written when a value changes or 15 minutes have passed, and the file is pruned to the retention period at launch.

**Concurrency.** UI state is `@MainActor`. Providers and parsers are `Sendable` value types that run off the main actor. `HistoryStore` is an actor.

## Provider capabilities

| | Claude | Codex |
| --- | --- | --- |
| Source | Status line JSON (`rate_limits`), or the account endpoint when opted in | Codex CLI session logs (`token_count` events) |
| Documented | Status line: yes. Account endpoint: no | No. Observed in codex-cli 0.159; older `resets_in_seconds` form also handled |
| Session / 5-hour window | Yes | Yes (`primary`, 300 min) |
| Weekly window | Yes | Yes (`secondary`, 10080 min) |
| Reset time | Yes | Yes |
| Other | `spend_limit` behind a gateway, shown as Spend Limit | Plan type |
| Needs authentication by QuotaBar | Status line: no. Account endpoint: Claude Code's Keychain token, read-only | No |
| Updates when | Status line: Claude Code renders it (terminal CLI). Account endpoint: every refresh, at most every two minutes | Codex receives a response |

Both formats can change. Each change is contained in that provider's `Models` and `Parser` files, and the fixtures in the tests show the shapes currently handled.

## Adding a provider

1. Add a case to `AIProvider` (name, short code, symbol, CLI name).
2. Implement `UsageProvider` under `Providers/<Name>/`, with a pure parser and tests.
3. Return it from `AppEnvironment.makeProviders`.

The store, cache, history, notifications, menu and the Notifications settings tab iterate over `AIProvider.allCases` and need no changes. A provider-specific settings tab is one line in `SettingsView`.

## Testing

Tests run inside the app process. `AppEnvironment.isRunningTests` stops the hosted app from refreshing, scheduling or prompting. Everything that touches the file system takes an `AppPaths`, which tests point at a temporary directory. The bridge tests install into a temporary home and execute the real script.

`ScreenshotTests` renders the menu and a settings tab with mock data into `docs/`. It is skipped unless `QUOTABAR_SCREENSHOTS` is set (`make screenshots`).
