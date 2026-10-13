# Security

QuotaBar has no backend, no account of its own, no analytics, and no telemetry. By default it is local-only. One optional setting, off by default, reads a credential and makes a network request; it is described first.

## The optional Anthropic account source

**Settings → Claude → Read usage from my Anthropic account** is off by default. With it off, QuotaBar reads no credentials and makes no network requests.

With it on:

- **Credential read:** the Keychain item `Claude Code-credentials`, which Claude Code creates when you sign in. macOS shows its own dialog asking you to allow QuotaBar to read it. QuotaBar uses only the access token and its expiry time.
- **Where the token goes:** in an `Authorization` header to `https://api.anthropic.com/api/oauth/usage`, and nowhere else. This is the endpoint behind Claude Code's Account & Usage panel. It is not officially documented.
- **Storage:** the token is held in memory until it expires. It is never written to disk, UserDefaults, the log, or the diagnostics report.
- **No refresh:** QuotaBar never uses the refresh token. Renewing the session would rotate it and sign Claude Code out, so an expired session is reported as "sign-in expired" until Claude Code renews it.
- **Request rate:** at most one request every two minutes, whatever the refresh interval.
- **Response:** only the usage percentages and reset times are kept.
- **If you click Deny:** QuotaBar does not ask again for 15 minutes, or until you switch the setting off and on.

The code is in `KeychainReader.swift` and `ClaudeAccountUsageSource.swift`. Unit tests assert the request URL and that an expired token is never sent.

## Network requests

Only the request above, and only when that setting is on. Nothing else in the app uses the network.

Two macOS services are used and behave as they do for any app: UserNotifications (local alerts) and ServiceManagement (the login item).

## Credentials

- **Claude:** the Keychain item is read only when the account source is on, as described above.
- **Codex:** QuotaBar checks whether `~/.codex/auth.json` *exists* to tell "not signed in" apart from "no sessions yet". It never opens the file.

QuotaBar stores no credentials of its own.

## Files read

| Path | Purpose |
| --- | --- |
| `~/Library/Application Support/QuotaBar/claude-statusline.json` | Claude rate limits saved by the bridge script |
| `~/.codex/sessions/**/rollout-*.jsonl` | Newest Codex session logs. Only lines containing `rate_limits` are decoded, and only that object, the event type and the timestamp are kept in memory. Conversation content in these files is skipped and never stored, logged or exported. |
| `~/.claude/settings.json` | Read to check whether the bridge is installed |
| Keychain item `Claude Code-credentials` | Only with the account source on |
| Standard binary directories (`/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, …) | Locating the `claude` and `codex` executables |

## Files written

Everything QuotaBar creates is in `~/Library/Application Support/QuotaBar`:

| File | Contents |
| --- | --- |
| `usage-cache.json` | Last successful reading per provider |
| `history.jsonl` | Timestamp, provider, window type, percentage |
| `notification-state.json` | Which alert thresholds have fired in the current window |
| `claude-statusline.json` | The `rate_limits` object from Claude Code |
| `quotabar-statusline.sh`, `statusline-chain-command`, `statusline-original.json` | The bridge script and your previous status line, kept for restore |

Preferences are in UserDefaults (`com.pouya.QuotaBar`) and hold no secrets.

One file outside that directory is modified, and only when you press **Install** or **Remove** in Settings → Claude: `~/.claude/settings.json`. The `statusLine` key is set to the bridge script, every other key is preserved, and a copy of the file is saved as `settings.json.quotabar-backup` first. If the file is not valid JSON, QuotaBar leaves it untouched.

## The bridge script

Claude Code runs the script and pipes its status JSON to it. That payload also contains the working directory, session id and cost. The script extracts only `rate_limits` with `/usr/bin/plutil` and discards the rest, then runs your previous status line command, if you had one, with the original payload. It makes no network requests. The source is in `ClaudeStatusLineBridge.swift`, and a unit test asserts that session data does not reach the snapshot file.

## Processes started

- `claude --version` and `codex --version`, only when you export diagnostics
- `/bin/zsh -l -c 'command -v -- "$1"' -- <tool>`, only when a tool is not in the standard directories

Executables are run by absolute path with an argument array, never through a shell string, and with a timeout. The tool name passed to `zsh` is a positional argument from a fixed list.

## Logs and diagnostics

Log messages pass through a redactor (bearer tokens, API-key shapes, JWTs, `token=`/`secret=`/`cookie=` values) before reaching the unified log or the in-memory buffer. The diagnostics export contains versions, tool paths with the home directory abbreviated, provider state and recent log lines. It is written only where you choose to save it.

## Sandbox

The App Sandbox is disabled, because the app must read `~/.codex` and `~/.claude` and run the CLIs. Release builds use the Hardened Runtime.

## Reporting a problem

Open an issue in the repository. Do not include tokens or the contents of `auth.json`.
