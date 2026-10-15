using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using Microsoft.Win32;

namespace QuotaBar.App;

/// Colours that follow the Windows light/dark app setting.
public sealed record Theme(Color Background, Color Card, Color Text, Color Secondary, Color Track, Color Border)
{
    public static readonly Color Normal = Color.FromArgb(52, 168, 83);
    public static readonly Color Warning = Color.FromArgb(242, 153, 0);
    public static readonly Color Critical = Color.FromArgb(217, 48, 37);
    public static readonly Color Accent = Color.FromArgb(217, 119, 87);

    public static bool IsDark
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int light && light == 0;
        }
    }

    public static bool IsTaskbarDark
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("SystemUsesLightTheme") is not int light || light == 0;
        }
    }

    public static Theme Current => IsDark
        ? new Theme(Color.FromArgb(32, 32, 32), Color.FromArgb(44, 44, 44), Color.FromArgb(240, 240, 240),
            Color.FromArgb(160, 160, 160), Color.FromArgb(70, 70, 70), Color.FromArgb(60, 60, 60))
        : new Theme(Color.FromArgb(243, 243, 243), Color.White, Color.FromArgb(28, 28, 28),
            Color.FromArgb(105, 105, 105), Color.FromArgb(225, 225, 225), Color.FromArgb(220, 220, 220));

    public static Color ForPercentage(double percentage) =>
        percentage >= 90 ? Critical : percentage >= 80 ? Warning : Normal;

    public static GraphicsPath RoundedRectangle(RectangleF bounds, float radius)
    {
        var path = new GraphicsPath();
        var diameter = Math.Min(radius * 2, Math.Min(bounds.Width, bounds.Height));
        if (diameter <= 0)
        {
            path.AddRectangle(bounds);
            return path;
        }
        path.AddArc(bounds.X, bounds.Y, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Y, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.X, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    /// Dark title bar for windows when Windows is in dark mode.
    public static void ApplyTitleBar(Form form)
    {
        var dark = IsDark ? 1 : 0;
        _ = DwmSetWindowAttribute(form.Handle, 20, ref dark, sizeof(int));
    }

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
}
