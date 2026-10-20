using System.Drawing.Drawing2D;
using System.Drawing.Text;
using QuotaBar.Core;

namespace QuotaBar.App;

/// Shared painting for the panel and the widget. Everything is laid out in
/// 96-DPI units and scaled with a transform, so it looks the same at any scaling.
public static class Draw
{
    public static Font Font(float pixels, bool bold = false) =>
        new(bold ? "Segoe UI Semibold" : "Segoe UI", pixels, FontStyle.Regular, GraphicsUnit.Pixel);

    public static void Prepare(Graphics g, float scale)
    {
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
        g.ScaleTransform(scale, scale);
    }

    public static void Bar(Graphics g, RectangleF bar, double percentage, Theme theme)
    {
        var radius = bar.Height / 2;
        using (var track = new SolidBrush(theme.Track))
        using (var trackPath = Theme.RoundedRectangle(bar, radius))
            g.FillPath(track, trackPath);
        if (percentage <= 0) return;
        var fill = bar with { Width = Math.Max(bar.Height, bar.Width * (float)(Math.Min(percentage, 100) / 100)) };
        using var brush = new SolidBrush(Theme.ForPercentage(percentage));
        using var fillPath = Theme.RoundedRectangle(fill, radius);
        g.FillPath(brush, fillPath);
    }

    public static void TextRight(Graphics g, string text, Font font, Brush brush, float right, float y)
    {
        var size = g.MeasureString(text, font);
        g.DrawString(text, font, brush, right - size.Width, y);
    }
}

/// The flyout shown when the tray icon is clicked: one card per provider and a
/// footer with Refresh, Settings and Quit. It hides itself when it loses focus.
public sealed class UsagePanel : Form
{
    private const int PanelWidth = 320;
    private const int Pad = 14;
    private const int HeaderHeight = 26;
    private const int WindowHeight = 50;
    private const int ErrorHeight = 36;
    private const int ReconnectHeight = 30;

    private readonly UsageStore _store;
    private readonly Func<AppSettings> _settings;
    private readonly List<(RectangleF Bounds, string Name, Action Action)> _buttons = [];
    private readonly System.Windows.Forms.Timer _ticker = new() { Interval = 15_000 };
    private string? _hovered;

    public event Action? RefreshRequested;
    public event Action<AIProvider>? ReconnectRequested;
    public event Action? SettingsRequested;
    public event Action? WidgetRequested;
    public event Action? QuitRequested;

    public UsagePanel(UsageStore store, Func<AppSettings> settings)
    {
        _store = store;
        _settings = settings;
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        StartPosition = FormStartPosition.Manual;
        TopMost = true;
        DoubleBuffered = true;
        KeyPreview = true;
        _ticker.Tick += (_, _) => Invalidate();
        _store.Changed += () =>
        {
            if (IsHandleCreated && Visible) BeginInvoke(Relayout);
        };
    }

    private float DpiScale => DeviceDpi / 96f;

    protected override CreateParams CreateParams
    {
        get
        {
            const int dropShadow = 0x00020000;
            var parameters = base.CreateParams;
            parameters.ClassStyle |= dropShadow;
            return parameters;
        }
    }

    public void ShowNear(Point anchor)
    {
        Relayout();
        var area = Screen.FromPoint(anchor).WorkingArea;
        var x = Math.Clamp(anchor.X - Width / 2, area.Left + 8, area.Right - Width - 8);
        // The taskbar is usually at the bottom; open above it, else at the top.
        var y = anchor.Y > area.Top + area.Height / 2 ? area.Bottom - Height - 8 : area.Top + 8;
        Location = new Point(x, y);
        Show();
        Activate();
        _ticker.Start();
    }

    protected override void OnDeactivate(EventArgs e)
    {
        base.OnDeactivate(e);
        HidePanel();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        base.OnKeyDown(e);
        if (e.KeyCode == Keys.Escape) HidePanel();
    }

    private void HidePanel()
    {
        _ticker.Stop();
        Hide();
    }

    private void Relayout()
    {
        Width = (int)Math.Ceiling(PanelWidth * DpiScale);
        Height = (int)Math.Ceiling(ContentHeight() * DpiScale);
        using var path = Theme.RoundedRectangle(new RectangleF(0, 0, Width, Height), 8 * DpiScale);
        Region = new Region(path);
        Invalidate();
    }

    private List<AIProvider> ShownProviders()
    {
        var settings = _settings();
        return Enum.GetValues<AIProvider>().Where(p => p == AIProvider.Claude ? settings.ClaudeEnabled : settings.CodexEnabled).ToList();
    }

    private float ContentHeight()
    {
        var providers = ShownProviders();
        float height = Pad + 30;
        height += providers.Count == 0 ? 24 : providers.Sum(p => CardHeight(_store.Snapshots[p]) + 10);
        return height + 30 + 18 + Pad;
    }

    private static float CardHeight(ProviderSnapshot snapshot)
    {
        float height = 8 + HeaderHeight;
        if (snapshot.Usage is { } usage) height += usage.Windows.Count * WindowHeight;
        if (snapshot.LastError is not null) height += ErrorHeight;
        if (NeedsReconnect(snapshot)) height += ReconnectHeight;
        else if (snapshot.Usage is null) height += 22;
        return height + 4;
    }

    /// Sign-in problems are fixed by signing in again, so the card offers it.
    private static bool NeedsReconnect(ProviderSnapshot snapshot) =>
        snapshot.LastError?.Kind is ProviderErrorKind.SessionExpired or ProviderErrorKind.AuthenticationRequired;

    protected override void OnPaint(PaintEventArgs e)
    {
        var g = e.Graphics;
        var theme = Theme.Current;
        var now = DateTimeOffset.Now;
        g.Clear(theme.Background);
        Draw.Prepare(g, DpiScale);
        _buttons.Clear();

        using var titleFont = Draw.Font(15, bold: true);
        using var boldFont = Draw.Font(13, bold: true);
        using var bodyFont = Draw.Font(12);
        using var smallFont = Draw.Font(11);
        using var text = new SolidBrush(theme.Text);
        using var secondary = new SolidBrush(theme.Secondary);

        float y = Pad;
        g.DrawString("QuotaBar", titleFont, text, Pad, y);
        y += 30;

        var providers = ShownProviders();
        if (providers.Count == 0)
        {
            g.DrawString("No providers enabled. Turn one on in Settings.", bodyFont, secondary, Pad, y);
            y += 24;
        }

        foreach (var provider in providers)
        {
            var snapshot = _store.Snapshots[provider];
            var cardHeight = CardHeight(snapshot);
            var card = new RectangleF(Pad - 4, y, PanelWidth - 2 * (Pad - 4), cardHeight);
            using (var cardPath = Theme.RoundedRectangle(card, 6))
            using (var cardBrush = new SolidBrush(theme.Card))
            using (var border = new Pen(theme.Border))
            {
                g.FillPath(cardBrush, cardPath);
                g.DrawPath(border, cardPath);
            }

            float x = Pad + 6;
            float right = PanelWidth - Pad - 6;
            var rowY = y + 8;
            var name = provider.DisplayName() + (snapshot.Usage?.PlanName is { } plan ? $"  ·  {plan}" : "");
            g.DrawString(name, boldFont, text, x, rowY);
            if (snapshot.Usage is { } reading)
            {
                var age = (snapshot.IsStale ? "Stale · " : "") + Formatting.Ago(reading.UpdatedAt, now);
                Draw.TextRight(g, age, smallFont, secondary, right, rowY + 2);
            }
            rowY += HeaderHeight;

            if (snapshot.Usage is { } usage)
            {
                foreach (var window in usage.Windows)
                {
                    var percentage = window.EffectivePercentage(now);
                    g.DrawString(window.Title, bodyFont, text, x, rowY);
                    Draw.TextRight(g, $"{UsageMath.DisplayPercent(percentage)}%", boldFont, text, right, rowY - 1);
                    Draw.Bar(g, new RectangleF(x, rowY + 19, right - x, 6), percentage, theme);
                    var reset = Formatting.Reset(window, now);
                    if (window.EstimatedCost is { } cost) reset += $" · ${cost:0.00} spent";
                    g.DrawString(reset, smallFont, secondary, x, rowY + 28);
                    rowY += WindowHeight;
                }
            }
            if (snapshot.LastError is { } error)
            {
                using var errorBrush = new SolidBrush(snapshot.Usage is null ? theme.Text : Theme.Warning);
                g.DrawString(error.Message, smallFont, errorBrush, new RectangleF(x, rowY, right - x, ErrorHeight));
                rowY += ErrorHeight;
                if (NeedsReconnect(snapshot))
                {
                    var label = "Reconnect";
                    var key = $"reconnect-{provider}";
                    var size = g.MeasureString(label, bodyFont);
                    var bounds = new RectangleF(x, rowY, size.Width + 20, 24);
                    var target = provider;
                    _buttons.Add((bounds, key, () => { HidePanel(); ReconnectRequested?.Invoke(target); }));
                    using var buttonPath = Theme.RoundedRectangle(bounds, 4);
                    using var buttonBrush = new SolidBrush(_hovered == key ? ControlPaint.Dark(Theme.Accent, 0.1f) : Theme.Accent);
                    g.FillPath(buttonBrush, buttonPath);
                    g.DrawString(label, bodyFont, Brushes.White, bounds.X + 10, bounds.Y + (bounds.Height - size.Height) / 2);
                }
            }
            else if (snapshot.Usage is null)
            {
                g.DrawString(_store.IsRefreshing ? "Updating…" : "Unavailable", smallFont, secondary, x, rowY);
            }
            y += cardHeight + 10;
        }

        // Footer: status on its own line above the buttons so they never overlap.
        var status = _store.IsRefreshing ? "Updating…"
            : _store.LastRefresh is { } last ? $"Updated {Formatting.Ago(last, now)}" : "Not updated yet";
        float buttonX = PanelWidth - Pad + 6;
        foreach (var (label, action) in new (string, Action)[]
                 {
                     ("Quit", () => QuitRequested?.Invoke()),
                     ("Settings", () => { HidePanel(); SettingsRequested?.Invoke(); }),
                     ("Widget", () => { HidePanel(); WidgetRequested?.Invoke(); }),
                     ("Refresh", () => RefreshRequested?.Invoke()),
                 })
        {
            var size = g.MeasureString(label, bodyFont);
            var bounds = new RectangleF(buttonX - size.Width - 10, y, size.Width + 10, 24);
            buttonX = bounds.Left - 2;
            _buttons.Add((bounds, label, action));
            if (_hovered == label)
            {
                using var hover = new SolidBrush(theme.Track);
                using var hoverPath = Theme.RoundedRectangle(bounds, 4);
                g.FillPath(hover, hoverPath);
            }
            g.DrawString(label, bodyFont, text, bounds.X + 5, bounds.Y + (bounds.Height - size.Height) / 2);
        }
        y += 30;
        g.DrawString(status, smallFont, secondary, Pad, y);
        // The credit opens the GitHub repository.
        var credit = "Engineered by P.Mansournia";
        var creditSize = g.MeasureString(credit, smallFont);
        var creditBounds = new RectangleF(PanelWidth - Pad - creditSize.Width, y, creditSize.Width, creditSize.Height);
        _buttons.Add((creditBounds, "credit", () => { HidePanel(); AppInfo.Open(AppInfo.RepositoryUrl); }));
        using (var creditBrush = new SolidBrush(_hovered == "credit" ? Theme.Accent : theme.Secondary))
            g.DrawString(credit, smallFont, creditBrush, creditBounds.X, y);
    }

    private PointF Logical(Point point) => new(point.X / DpiScale, point.Y / DpiScale);

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        var location = Logical(e.Location);
        var hovered = _buttons.FirstOrDefault(b => b.Bounds.Contains(location)).Name;
        if (hovered == _hovered) return;
        _hovered = hovered;
        Cursor = hovered is null ? Cursors.Default : Cursors.Hand;
        Invalidate();
    }

    protected override void OnMouseLeave(EventArgs e)
    {
        base.OnMouseLeave(e);
        _hovered = null;
        Invalidate();
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        var location = Logical(e.Location);
        _buttons.FirstOrDefault(b => b.Bounds.Contains(location)).Action?.Invoke();
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing) _ticker.Dispose();
        base.Dispose(disposing);
    }
}
