using System.Runtime.InteropServices;
using QuotaBar.Core;

namespace QuotaBar.App;

/// A small always-visible desktop widget: one row per window for each provider.
/// Drag it anywhere; double-click opens the full panel, right-click the menu.
/// Its position is remembered.
public sealed class UsageWidget : Form
{
    private const int WidgetWidth = 220;
    private const int Pad = 10;
    private const int NameHeight = 18;
    private const int RowHeight = 17;

    private readonly UsageStore _store;
    private readonly Func<AppSettings> _settings;
    private readonly ToolTip _toolTip = new();
    private readonly System.Windows.Forms.Timer _ticker = new() { Interval = 30_000 };

    public event Action? OpenPanelRequested;
    public event Action<Point>? Moved;

    public UsageWidget(UsageStore store, Func<AppSettings> settings, ContextMenuStrip menu)
    {
        _store = store;
        _settings = settings;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        DoubleBuffered = true;
        ContextMenuStrip = menu;
        Opacity = 0.96;
        _ticker.Tick += (_, _) => Relayout();
        _store.Changed += () =>
        {
            if (IsHandleCreated) BeginInvoke(Relayout);
        };
    }

    private float DpiScale => DeviceDpi / 96f;

    protected override CreateParams CreateParams
    {
        get
        {
            const int toolWindow = 0x00000080; // keeps it out of Alt+Tab
            const int dropShadow = 0x00020000;
            var parameters = base.CreateParams;
            parameters.ExStyle |= toolWindow;
            parameters.ClassStyle |= dropShadow;
            return parameters;
        }
    }

    protected override bool ShowWithoutActivation => true;

    public void ShowWidget()
    {
        var settings = _settings();
        TopMost = settings.WidgetOnTop;
        Relayout();
        var area = Screen.PrimaryScreen!.WorkingArea;
        var location = settings.WidgetX is { } x && settings.WidgetY is { } y
            ? new Point(x, y)
            : new Point(area.Right - Width - 16, area.Bottom - Height - 16);
        // Keep it on a screen that still exists (monitors can be unplugged).
        if (!Screen.AllScreens.Any(s => s.WorkingArea.IntersectsWith(new Rectangle(location, Size))))
            location = new Point(area.Right - Width - 16, area.Bottom - Height - 16);
        Location = location;
        Show();
        _ticker.Start();
    }

    public void HideWidget()
    {
        _ticker.Stop();
        Hide();
    }

    private List<(AIProvider Provider, ProviderSnapshot Snapshot)> Rows()
    {
        var settings = _settings();
        return Enum.GetValues<AIProvider>()
            .Where(p => p == AIProvider.Claude ? settings.ClaudeEnabled : settings.CodexEnabled)
            .Select(p => (p, _store.Snapshots[p]))
            .ToList();
    }

    private static int LineCount(ProviderSnapshot snapshot) => Math.Max(1, snapshot.Usage?.Windows.Count ?? 1);

    private void Relayout()
    {
        var rows = Rows();
        float height = Pad * 2 + rows.Sum(r => NameHeight + LineCount(r.Snapshot) * RowHeight) + Math.Max(0, rows.Count - 1) * 6;
        if (rows.Count == 0) height = Pad * 2 + RowHeight;
        Width = (int)Math.Ceiling(WidgetWidth * DpiScale);
        Height = (int)Math.Ceiling(height * DpiScale);
        using var path = Theme.RoundedRectangle(new RectangleF(0, 0, Width, Height), 10 * DpiScale);
        Region = new Region(path);
        UpdateToolTip();
        Invalidate();
    }

    private void UpdateToolTip()
    {
        var now = DateTimeOffset.Now;
        var lines = new List<string>();
        foreach (var (provider, snapshot) in Rows())
        {
            if (snapshot.Usage is { } usage)
            {
                foreach (var window in usage.Windows)
                    lines.Add($"{provider.DisplayName()} {window.Title}: {Formatting.Reset(window, now)}");
                lines.Add($"   updated {Formatting.Ago(usage.UpdatedAt, now)}");
            }
            if (snapshot.LastError is { } error) lines.Add($"{provider.DisplayName()}: {error.Message}");
        }
        lines.Add("Double-click for details · drag to move");
        _toolTip.SetToolTip(this, string.Join("\n", lines));
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        var theme = Theme.Current;
        var now = DateTimeOffset.Now;
        g.Clear(theme.Card);
        Draw.Prepare(g, DpiScale);

        using var nameFont = Draw.Font(12, bold: true);
        using var labelFont = Draw.Font(11);
        using var valueFont = Draw.Font(11, bold: true);
        using var text = new SolidBrush(theme.Text);
        using var secondary = new SolidBrush(theme.Secondary);
        using (var border = new Pen(theme.Border))
        using (var outline = Theme.RoundedRectangle(new RectangleF(0.5f, 0.5f, WidgetWidth - 1, Height / DpiScale - 1), 10))
            g.DrawPath(border, outline);

        var rows = Rows();
        float y = Pad;
        if (rows.Count == 0)
        {
            g.DrawString("No providers enabled", labelFont, secondary, Pad, y);
            return;
        }

        const float labelWidth = 26;
        const float valueWidth = 38;
        float right = WidgetWidth - Pad;
        foreach (var (provider, snapshot) in rows)
        {
            var name = provider.DisplayName() + (snapshot.Usage?.PlanName is { } plan ? $" · {plan}" : "");
            g.DrawString(name, nameFont, text, Pad - 2, y);
            if (snapshot.IsStale) Draw.TextRight(g, "stale", labelFont, secondary, right, y + 1);
            y += NameHeight;

            if (snapshot.Usage is { } usage)
            {
                foreach (var window in usage.Windows)
                {
                    var percentage = window.EffectivePercentage(now);
                    g.DrawString(ShortTitle(window), labelFont, secondary, Pad - 2, y);
                    Draw.Bar(g, new RectangleF(Pad + labelWidth, y + 6, right - Pad - labelWidth - valueWidth, 5), percentage, theme);
                    Draw.TextRight(g, $"{UsageMath.DisplayPercent(percentage)}%", valueFont, text, right, y);
                    y += RowHeight;
                }
            }
            else
            {
                var message = snapshot.LastError?.Message ?? (_store.IsRefreshing ? "Updating…" : "Unavailable");
                g.DrawString(message, labelFont, secondary, new RectangleF(Pad - 2, y, right - Pad, RowHeight), new StringFormat { Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap });
                y += RowHeight;
            }
            y += 6;
        }
    }

    private static string ShortTitle(UsageWindow window) => window.Type switch
    {
        UsageWindowType.FiveHour => "5h",
        UsageWindowType.Weekly => "7d",
        UsageWindowType.Daily => "1d",
        UsageWindowType.Monthly => "mo",
        UsageWindowType.ApiBudget => "$",
        _ => window.Label ?? "—",
    };

    protected override void OnMouseDown(MouseEventArgs e)
    {
        base.OnMouseDown(e);
        if (e.Button != MouseButtons.Left || e.Clicks > 1) return;
        // Let Windows move the window as if the whole widget were a title bar.
        ReleaseCapture();
        SendMessage(Handle, 0xA1 /* WM_NCLBUTTONDOWN */, (IntPtr)2 /* HTCAPTION */, IntPtr.Zero);
    }

    protected override void WndProc(ref Message m)
    {
        const int WM_NCLBUTTONDBLCLK = 0xA3;
        const int WM_EXITSIZEMOVE = 0x232;
        if (m.Msg == WM_NCLBUTTONDBLCLK)
        {
            OpenPanelRequested?.Invoke();
            return;
        }
        base.WndProc(ref m);
        if (m.Msg == WM_EXITSIZEMOVE) Moved?.Invoke(Location);
    }

    protected override void OnDpiChanged(DpiChangedEventArgs e)
    {
        base.OnDpiChanged(e);
        Relayout();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _ticker.Dispose();
            _toolTip.Dispose();
        }
        base.Dispose(disposing);
    }

    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();

    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
}
