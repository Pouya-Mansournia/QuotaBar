using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;

namespace QuotaBar.App;

/// Draws the notification-area icon: a gauge ring with the percentage inside,
/// so the value is readable without opening the panel.
public static class TrayIconRenderer
{
    public static Icon Render(int? percentage, bool stale)
    {
        var size = Math.Max(16, SystemInformation.SmallIconSize.Width);
        using var bitmap = new Bitmap(size, size);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            graphics.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            graphics.Clear(Color.Transparent);

            var foreground = Theme.IsTaskbarDark ? Color.White : Color.Black;
            var stroke = size / 8f;
            var ring = new RectangleF(stroke / 2, stroke / 2, size - stroke, size - stroke);
            using (var track = new Pen(Color.FromArgb(90, foreground), stroke))
                graphics.DrawEllipse(track, ring);

            if (percentage is { } value)
            {
                var colour = stale ? Color.Gray : Theme.ForPercentage(value);
                using var arc = new Pen(colour, stroke) { StartCap = LineCap.Round, EndCap = LineCap.Round };
                if (value > 0) graphics.DrawArc(arc, ring, -90, 360f * Math.Min(value, 100) / 100f);

                var text = value >= 100 ? "!" : value.ToString();
                using var font = new Font("Segoe UI", size * (text.Length > 1 ? 0.36f : 0.46f), FontStyle.Bold, GraphicsUnit.Pixel);
                using var brush = new SolidBrush(foreground);
                var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center };
                graphics.DrawString(text, font, brush, new RectangleF(0, 0.5f, size, size), format);
            }
            else
            {
                using var dash = new Pen(foreground, stroke);
                graphics.DrawLine(dash, size * 0.33f, size / 2f, size * 0.67f, size / 2f);
            }
        }

        var handle = bitmap.GetHicon();
        try
        {
            return (Icon)Icon.FromHandle(handle).Clone();
        }
        finally
        {
            DestroyIcon(handle);
        }
    }

    [DllImport("user32.dll")]
    private static extern bool DestroyIcon(IntPtr handle);
}
