using QuotaBar.Core;
using QuotaBar.Providers;

namespace QuotaBar.App;

/// Settings, also shown on first launch as the setup window.
public sealed class SettingsForm : Form
{
    private readonly AppSettings _settings;
    private readonly AppPaths _paths;
    private readonly ClaudeStatusLineBridge _bridge;

    private readonly CheckBox _claudeEnabled = new() { Text = "Show Claude", AutoSize = true };
    private readonly RadioButton _accountSource = new() { Text = "Read usage from my Anthropic account (recommended)", AutoSize = true };
    private readonly RadioButton _bridgeSource = new() { Text = "Status line bridge (no network; updates only while Claude Code runs in a terminal)", AutoSize = true };
    private readonly Label _claudeStatus = new() { AutoSize = true, MaximumSize = new Size(470, 0) };
    private readonly Button _bridgeButton = new() { AutoSize = true };
    private readonly CheckBox _codexEnabled = new() { Text = "Show Codex", AutoSize = true };
    private readonly Label _codexStatus = new() { AutoSize = true, MaximumSize = new Size(470, 0) };
    private readonly ComboBox _trayDisplay = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
    private readonly ComboBox _refresh = new() { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
    private readonly CheckBox _showWidget = new() { Text = "Show desktop widget", AutoSize = true };
    private readonly CheckBox _widgetOnTop = new() { Text = "Keep widget on top of other windows", AutoSize = true };
    private readonly CheckBox _launchAtLogin = new() { Text = "Launch at login", AutoSize = true };
    private readonly CheckBox _notifications = new() { Text = "Notify when usage crosses", AutoSize = true };
    private readonly TextBox _thresholds = new() { Width = 120 };

    private static readonly int[] RefreshChoices = [60, 120, 300, 600];

    public event Action? Saved;

    public SettingsForm(AppSettings settings, AppPaths paths, ClaudeStatusLineBridge bridge, bool firstRun)
    {
        _settings = settings;
        _paths = paths;
        _bridge = bridge;

        Text = firstRun ? "Welcome to QuotaBar" : "QuotaBar Settings";
        Font = new Font("Segoe UI", 9f);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Icon = Program.AppIcon;

        var theme = Theme.Current;
        BackColor = theme.Background;
        ForeColor = theme.Text;

        var layout = new FlowLayoutPanel
        {
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            AutoSize = true,
            Padding = new Padding(16),
        };
        Controls.Add(layout);

        if (firstRun)
        {
            layout.Controls.Add(Paragraph(
                "QuotaBar lives in the notification area next to the clock and shows how much of your Claude and Codex " +
                "usage limits you have left. Click its icon to see details; the small desktop widget keeps the numbers in view (drag it anywhere, double-click for details). Tip: drag the icon out of the overflow (^) " +
                "onto the taskbar to keep it visible.", theme.Text));
        }

        layout.Controls.Add(Header("Claude"));
        layout.Controls.Add(_claudeEnabled);
        layout.Controls.Add(_accountSource);
        layout.Controls.Add(_bridgeSource);
        layout.Controls.Add(_bridgeButton);
        layout.Controls.Add(_claudeStatus);

        layout.Controls.Add(Header("Codex"));
        layout.Controls.Add(_codexEnabled);
        layout.Controls.Add(_codexStatus);

        layout.Controls.Add(Header("General"));
        layout.Controls.Add(Row("Tray icon shows", _trayDisplay));
        layout.Controls.Add(Row("Refresh every", _refresh));
        layout.Controls.Add(_showWidget);
        layout.Controls.Add(_widgetOnTop);
        layout.Controls.Add(_launchAtLogin);
        var notifyRow = Row(null, _notifications);
        notifyRow.Controls.Add(_thresholds);
        notifyRow.Controls.Add(new Label { Text = "%", AutoSize = true, Margin = new Padding(0, 6, 0, 0) });
        layout.Controls.Add(notifyRow);

        var buttons = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Width = 480, Margin = new Padding(0, 16, 0, 0) };
        var save = new Button { Text = firstRun ? "Get started" : "Save", AutoSize = true, DialogResult = DialogResult.OK };
        var cancel = new Button { Text = "Cancel", AutoSize = true, DialogResult = DialogResult.Cancel };
        buttons.Controls.Add(save);
        if (!firstRun) buttons.Controls.Add(cancel);
        layout.Controls.Add(buttons);
        AcceptButton = save;
        CancelButton = firstRun ? save : cancel;
        save.Click += (_, _) => Save();

        foreach (var button in new[] { save, cancel, _bridgeButton })
        {
            button.FlatStyle = FlatStyle.System;
        }

        _trayDisplay.Items.AddRange(["Highest usage", "Claude", "Codex"]);
        _refresh.Items.AddRange(["1 minute", "2 minutes", "5 minutes", "10 minutes"]);

        _claudeEnabled.Checked = settings.ClaudeEnabled;
        _accountSource.Checked = settings.ClaudeSource == ClaudeSource.Account;
        _bridgeSource.Checked = settings.ClaudeSource == ClaudeSource.StatusLine;
        _codexEnabled.Checked = settings.CodexEnabled;
        _trayDisplay.SelectedIndex = (int)settings.TrayDisplay;
        _refresh.SelectedIndex = Math.Max(0, Array.IndexOf(RefreshChoices, settings.RefreshSeconds));
        _showWidget.Checked = settings.ShowWidget;
        _widgetOnTop.Checked = settings.WidgetOnTop;
        _launchAtLogin.Checked = LaunchAtLogin.IsEnabled;
        _notifications.Checked = settings.NotificationsEnabled;
        _thresholds.Text = string.Join(", ", settings.Thresholds);

        _accountSource.CheckedChanged += (_, _) => UpdateClaudeStatus();
        _bridgeButton.Click += (_, _) => ToggleBridge();
        UpdateClaudeStatus();
        _codexStatus.Text = Directory.Exists(paths.CodexSessionsDirectory)
            ? $"Reads rate limits from Codex CLI session logs ({paths.Abbreviated(paths.CodexSessionsDirectory)})."
            : "Codex CLI hasn't been used on this PC yet. Run `codex` once and QuotaBar picks it up.";
        _codexStatus.ForeColor = theme.Secondary;
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        Theme.ApplyTitleBar(this);
    }

    private void UpdateClaudeStatus()
    {
        var installed = _bridge.IsInstalled();
        _bridgeButton.Text = installed ? "Remove status line bridge" : "Install status line bridge";
        _bridgeButton.Visible = _bridgeSource.Checked || installed;
        _claudeStatus.ForeColor = Theme.Current.Secondary;

        if (_accountSource.Checked)
        {
            _claudeStatus.Text = File.Exists(_paths.ClaudeCredentialsFile)
                ? "Uses Claude Code's sign-in (~/.claude/.credentials.json) to ask api.anthropic.com for your usage, at most every two minutes. The token is never stored or sent anywhere else. Works with the VS Code extension too."
                : "Claude Code isn't signed in on this PC. Install Claude Code, run `claude` and sign in, then click Refresh.";
        }
        else
        {
            _claudeStatus.Text = installed
                ? "Installed. Send one message in a Claude Code terminal session to update the values."
                : "Install the bridge, then send one message in a Claude Code terminal session. Your existing status line keeps working.";
        }
    }

    private void ToggleBridge()
    {
        try
        {
            if (_bridge.IsInstalled()) _bridge.Uninstall();
            else _bridge.Install();
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            MessageBox.Show(this, exception.Message, "QuotaBar", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        UpdateClaudeStatus();
    }

    private void Save()
    {
        _settings.HasCompletedSetup = true;
        _settings.ClaudeEnabled = _claudeEnabled.Checked;
        _settings.ClaudeSource = _accountSource.Checked ? ClaudeSource.Account : ClaudeSource.StatusLine;
        _settings.CodexEnabled = _codexEnabled.Checked;
        _settings.TrayDisplay = (TrayDisplay)Math.Max(0, _trayDisplay.SelectedIndex);
        _settings.RefreshSeconds = RefreshChoices[Math.Max(0, _refresh.SelectedIndex)];
        _settings.ShowWidget = _showWidget.Checked;
        _settings.WidgetOnTop = _widgetOnTop.Checked;
        _settings.NotificationsEnabled = _notifications.Checked;
        var thresholds = _thresholds.Text
            .Split([',', ' ', ';'], StringSplitOptions.RemoveEmptyEntries)
            .Select(part => int.TryParse(part.Trim('%'), out var value) ? value : -1)
            .Where(value => value is > 0 and <= 100)
            .Distinct()
            .Order()
            .ToList();
        if (thresholds.Count > 0) _settings.Thresholds = thresholds;

        try
        {
            if (_launchAtLogin.Checked != LaunchAtLogin.IsEnabled) LaunchAtLogin.Set(_launchAtLogin.Checked);
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or System.Security.SecurityException)
        {
            MessageBox.Show(this, "Couldn't change the startup setting: " + exception.Message, "QuotaBar");
        }

        _settings.Save(_paths);
        Saved?.Invoke();
    }

    private static Label Header(string text) => new()
    {
        Text = text,
        AutoSize = true,
        Font = new Font("Segoe UI Semibold", 10.5f),
        Margin = new Padding(0, 12, 0, 4),
    };

    private static Label Paragraph(string text, Color colour) => new()
    {
        Text = text,
        AutoSize = true,
        MaximumSize = new Size(480, 0),
        ForeColor = colour,
        Margin = new Padding(0, 0, 0, 4),
    };

    private static FlowLayoutPanel Row(string? label, Control control)
    {
        var row = new FlowLayoutPanel { AutoSize = true, WrapContents = false, Margin = new Padding(0, 2, 0, 2) };
        if (label is not null)
            row.Controls.Add(new Label { Text = label, AutoSize = false, Width = 130, Height = 26, TextAlign = ContentAlignment.MiddleLeft });
        row.Controls.Add(control);
        return row;
    }
}
