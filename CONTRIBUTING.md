# Contributing

Thanks for helping improve QuotaBar. Bug reports, fixes and small focused improvements are welcome.

## Before you start

- For anything larger than a bug fix, open an issue first so the approach can be agreed.
- Keep the project's rules: **no third-party dependencies in the macOS app**, no analytics or telemetry, and no new network requests or credential reads without an explicit opt-in. See [SECURITY.md](SECURITY.md).
- Never paste tokens, `auth.json` or `.credentials.json` contents into issues, logs or tests.

## macOS app (Swift)

Requires macOS 14+ and Xcode 16+.

```sh
make test     # unit tests
make run      # build Debug and launch
```

Structure and design decisions are in [ARCHITECTURE.md](ARCHITECTURE.md).

## Windows app (C#)

Requires the .NET 8 SDK on Windows.

```powershell
cd Windows
dotnet test
dotnet run --project QuotaBar.Windows
```

See [Windows/README.md](Windows/README.md).

## Provider formats

Claude and Codex data formats can change. Keep each change inside that provider's parser, accept unknown fields, and add a test fixture with the new shape. Never guess a value: report it as unavailable or unsupported instead.

## Pull requests

- One topic per pull request, with tests for parser or logic changes.
- Both test suites that your change touches must pass (CI runs them).
- Describe what you verified by hand, especially UI changes (a screenshot helps).
