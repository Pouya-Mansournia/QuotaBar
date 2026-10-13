# Troubleshooting

Start with **Settings → Advanced → Provider refresh test**. It refreshes every provider and shows the result. **Export…** in the same tab saves a diagnostics report with no secrets in it.

## Claude

**I use the VS Code extension and Claude never shows data**
The extension does not run a status line. Turn on **Settings → Claude → Read usage from my Anthropic account** and click **Allow** (or **Always Allow**) in the macOS Keychain dialog.

**"QuotaBar wasn't allowed to read your Claude sign-in"**
The macOS password dialog was cancelled or declined. Click **Allow Access…** in the menu, type the password you use to unlock the Mac, and choose **Always Allow**.

**"Claude Code sign-in expired — open Claude Code to renew it"**
Claude Code renews its own session when it runs. Send one message in Claude Code, then press Refresh.

**"Unsupported provider response" with the account source on**
Anthropic changed the response of the usage endpoint. Export diagnostics (it lists the field names only) and open an issue. The status line bridge is the fallback.

**The Keychain dialog comes back after every rebuild**
"Always Allow" is tied to the app's code signature, which changes with each ad hoc build. A build signed with a Developer ID keeps the approval.

**"Claude isn't connected yet"**
Click **Set Up Claude…** in the menu and follow the window. Or, for the source without credentials, open Settings → Claude and press **Install** next to Status line bridge.

**"Waiting for Claude Code — send a message in a terminal session"**
The bridge is installed but has not been run yet. Send a message in Claude Code in a terminal. Claude Code sends rate limits only after the first response of a session.

**Still waiting after using Claude Code**
- Rate limits are sent only for Pro and Max subscriptions, not for API-key usage.
- The status line is part of the terminal CLI. The VS Code extension's chat panel does not run it, so usage from extension-only sessions is not captured. Running `claude` once in a terminal (the integrated terminal counts) updates the values.
- Check that `statusLine` in `~/.claude/settings.json` still points at `quotabar-statusline.sh`. A project-level `.claude/settings.json` with its own `statusLine` overrides it for that project.

**"Claude Code not installed"**
QuotaBar could not find `claude` in the standard directories or through your login shell. Confirm `which claude` works in a new terminal window.

**My own status line disappeared**
It should keep rendering through the bridge. If it does not, press **Remove** to restore the original setting. The file as it was before installing is at `~/.claude/settings.json.quotabar-backup`.

**The numbers look old**
Claude values change only when Claude Code reports them. The card shows "Last reported … ago". Usage from claude.ai appears with the next Claude Code message.

## Codex

**"Codex CLI not installed"**
`~/.codex` does not exist. Install the Codex CLI and run it once. If you use a custom location, `CODEX_HOME` must be set in the environment QuotaBar is launched from.

**"Codex authentication unavailable"**
Codex is installed but not signed in. Run `codex login`.

**"No Codex sessions found yet" / "Codex has not reported usage limits yet"**
Send one prompt with Codex. Limits are recorded with the first response.

**Both windows show "Window reset · waiting for new data"**
The reset time of the last recorded reading has passed, so the old percentage no longer applies. The next Codex response brings current values.

## General

**No menu bar item**
macOS hides items when the menu bar is full, especially on notched displays. Quit other menu bar apps or switch to **Icon only** in Settings → General.

**No notifications**
Check System Settings → Notifications → QuotaBar and Settings → Notifications in the app. Each threshold alerts once per quota window.

**Launch at login does not stick**
Run the app from `/Applications` (`make install`). If macOS asks, approve it in System Settings → General → Login Items. Builds run from the build folder change path and may be dropped.

**"Data may be stale"**
The last refresh failed, and the previous reading is shown. The line below it gives the reason.

**Start over**
Settings → Advanced → **Reset Cache** clears cached readings, alert state and history. To remove everything, press **Remove** in Settings → Claude, quit the app, and delete `~/Library/Application Support/QuotaBar`.
