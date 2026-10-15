using QuotaBar.Core;
using QuotaBar.Providers;

namespace QuotaBar.App;

/// Composition root: owns the tray icon, the refresh timer, the panel and alerts.
public sealed class TrayApplication : ApplicationContext
{
    private readonly AppPaths _paths = AppPaths.Live();
    private readonly AppSettings _settings;
    private readonly ClaudeStatusLineBridge _bridge;
    private readonly ClaudeAccountUsageSource _accountSource;
    private readonly UsageStore _store;
    private readonly ThresholdTracker _tracker;
    private readonly NotifyIcon _tray;
    private readonly UsagePanel _panel;
    private readonly UsageWidget _widget;
    private readonly ToolStripMenuItem _widgetItem;
    private readonly System.Windows.Forms.Timer _timer = new();
    private readonly Control _ui = new();
    private SettingsForm? _settingsForm;
    private DateTime _panelHiddenAt;

    public TrayApplication()
    {
        _settings = AppSettings.Load(_paths);
        _tracker = ThresholdTracker.Load(_paths);
        _bridge = new ClaudeStatusLineBridge(_paths);
        _accountSource = new ClaudeAccountUsageSource(new ClaudeCredentialsFile(_paths));
        _store = new UsageStore(
            [new ClaudeUsageProvider(_paths, _bridge, _accountSource, () => _settings.ClaudeSource), new OpenAIUsageProvider(_paths)],
            provider => provider == AIProvider.Claude ? _settings.ClaudeEnabled : _settings.CodexEnabled);
        _ui.CreateControl();

        _panel = new UsagePanel(_store, () => _settings);
        _panel.RefreshRequested += () => _ = RefreshAsync();
        _panel.SettingsRequested += () => ShowSettings(firstRun: false);
        _panel.QuitRequested += Quit;
        _panel.WidgetRequested += () => SetWidgetVisible(!_settings.ShowWidget);
        _panel.VisibleChanged += (_, _) =>
        {
            if (!_panel.Visible) _panelHiddenAt = DateTime.Now;
        };

        var menu = new ContextMenuStrip();
        menu.Items.Add("Show usage", null, (_, _) => TogglePanel());
        _widgetItem = new ToolStripMenuItem("Show widget", null, (_, _) => SetWidgetVisible(!_settings.ShowWidget));
        menu.Items.Add(_widgetItem);
        menu.Items.Add("Refresh now", null, (_, _) => _ = RefreshAsync());
        menu.Items.Add("Settings…", null, (_, _) => ShowSettings(firstRun: false));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit QuotaBar", null, (_, _) => Quit());

        _widget = new UsageWidget(_store, () => _settings, menu);
        _widget.OpenPanelRequested += () => _panel.ShowNear(new Point(_widget.Left + _widget.Width / 2, _widget.Top));
        _widget.Moved += location =>
        {
            _settings.WidgetX = location.X;
            _settings.WidgetY = location.Y;
            SaveSettings();
        };
        ApplyWidget();

        _tray = new NotifyIcon
        {
            Icon = TrayIconRenderer.Render(null, false),
            Text = "QuotaBar",
            ContextMenuStrip = menu,
            Visible = true,
        };
        _tray.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left) TogglePanel();
        };

        _store.Changed += () => _ui.BeginInvoke(OnStoreChanged);
        _timer.Tick += (_, _) => _ = RefreshAsync();
        ApplySchedule();

        Microsoft.Win32.SystemEvents.UserPreferenceChanged += (_, _) => _ui.BeginInvoke(UpdateTray);
        Microsoft.Win32.SystemEvents.PowerModeChanged += (_, e) =>
        {
            if (e.Mode == Microsoft.Win32.PowerModes.Resume) _ui.BeginInvoke(() => _ = RefreshAsync());
        };

        if (!_settings.HasCompletedSetup) _ui.BeginInvoke(() => ShowSettings(firstRun: true));
        _ = RefreshAsync();
    }

    private Task RefreshAsync() => _store.RefreshAsync();

    private void ApplySchedule()
    {
        _timer.Stop();
        _timer.Interval = Math.Max(60, _settings.RefreshSeconds) * 1000;
        _timer.Start();
    }

    private void TogglePanel()
    {
        // Clicking the icon while the panel is open first deactivates (hides) it;
        // don't immediately reopen it on the same click.
        if (_panel.Visible || (DateTime.Now - _panelHiddenAt).TotalMilliseconds < 300)
        {
            _panel.Hide();
            return;
        }
        _panel.ShowNear(Cursor.Position);
    }

    private void SetWidgetVisible(bool visible)
    {
        _settings.ShowWidget = visible;
        SaveSettings();
        ApplyWidget();
    }

    private void ApplyWidget()
    {
        _widgetItem.Checked = _settings.ShowWidget;
        if (_settings.ShowWidget) _widget.ShowWidget();
        else _widget.HideWidget();
    }

    private void SaveSettings()
    {
        try
        {
            _settings.Save(_paths);
        }
        catch (IOException)
        {
        }
    }

    private void ShowSettings(bool firstRun)
    {
        if (_settingsForm is { IsDisposed: false })
        {
            _settingsForm.Activate();
            return;
        }
        var previousSource = _settings.ClaudeSource;
        _settingsForm = new SettingsForm(_settings, _paths, _bridge, firstRun);
        _settingsForm.Saved += () =>
        {
            if (_settings.ClaudeSource != previousSource)
            {
                _accountSource.Reset();
                _store.Clear(AIProvider.Claude);
            }
            if (!_settings.ClaudeEnabled) _store.Clear(AIProvider.Claude);
            if (!_settings.CodexEnabled) _store.Clear(AIProvider.Codex);
            ApplySchedule();
            ApplyWidget();
            _ = RefreshAsync();
        };
        _settingsForm.FormClosed += (_, _) =>
        {
            if (firstRun) _panel.ShowNear(Cursor.Position);
        };
        _settingsForm.Show();
        _settingsForm.Activate();
    }

    private void OnStoreChanged()
    {
        UpdateTray();
        if (_store.IsRefreshing) return;

        if (!_settings.NotificationsEnabled) return;
        var now = DateTimeOffset.Now;
        var events = new List<ThresholdEvent>();
        foreach (var (_, snapshot) in _store.Snapshots)
        {
            if (snapshot.Usage is { } usage && snapshot.LastError is null)
                events.AddRange(_tracker.Evaluate(usage, _settings.Thresholds, now));
        }
        try
        {
            _tracker.Save(_paths);
        }
        catch (IOException)
        {
        }
        if (events.Count == 0) return;

        var top = events.MaxBy(e => e.Threshold)!;
        var message = string.Join("\n", events.Select(e =>
            $"{e.Provider.DisplayName()} {e.Window.Title}: {UsageMath.DisplayPercent(e.Window.EffectivePercentage(now))}% used · {Formatting.Reset(e.Window, now)}"));
        _tray.ShowBalloonTip(10_000, $"{top.Provider.DisplayName()} usage at {top.Threshold}%", message,
            top.Threshold >= 90 ? ToolTipIcon.Warning : ToolTipIcon.Info);
    }

    private void UpdateTray()
    {
        var now = DateTimeOffset.Now;
        var candidates = _store.Snapshots
            .Where(pair => _settings.TrayDisplay switch
            {
                TrayDisplay.Claude => pair.Key == AIProvider.Claude,
                TrayDisplay.Codex => pair.Key == AIProvider.Codex,
                _ => true,
            })
            .Where(pair => pair.Value.Usage is not null)
            .ToList();

        int? value = candidates.Count == 0
            ? null
            : UsageMath.DisplayPercent(candidates.Max(pair => pair.Value.Usage!.HighestPercentage(now)));
        var stale = candidates.Count > 0 && candidates.All(pair => pair.Value.IsStale);

        var old = _tray.Icon;
        _tray.Icon = TrayIconRenderer.Render(value, stale);
        old?.Dispose();

        var lines = new List<string> { "QuotaBar" };
        foreach (var (provider, snapshot) in _store.Snapshots)
        {
            if (snapshot.Usage is not { } usage) continue;
            var parts = usage.Windows.Select(w => $"{ShortTitle(w)} {UsageMath.DisplayPercent(w.EffectivePercentage(now))}%");
            lines.Add($"{provider.DisplayName()}: {string.Join(" · ", parts)}");
        }
        var tooltip = string.Join("\n", lines);
        // NotifyIcon.Text is limited to 127 characters.
        _tray.Text = tooltip.Length > 127 ? tooltip[..127] : tooltip;
    }

    private static string ShortTitle(UsageWindow window) => window.Type switch
    {
        UsageWindowType.FiveHour => "5h",
        UsageWindowType.Weekly => "wk",
        UsageWindowType.Daily => "day",
        UsageWindowType.Monthly => "mo",
        UsageWindowType.ApiBudget => "$",
        _ => window.Label ?? "limit",
    };

    private void Quit()
    {
        _tray.Visible = false;
        _timer.Stop();
        ExitThread();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _tray.Dispose();
            _timer.Dispose();
            _panel.Dispose();
            _widget.Dispose();
            _ui.Dispose();
        }
        base.Dispose(disposing);
    }
}
