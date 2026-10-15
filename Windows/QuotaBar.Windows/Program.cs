using QuotaBar.App;

namespace QuotaBar;

internal static class Program
{
    public static Icon? AppIcon { get; private set; }

    [STAThread]
    private static void Main()
    {
        // One instance per user session.
        using var mutex = new Mutex(initiallyOwned: true, @"Local\QuotaBar.SingleInstance", out var isFirst);
        if (!isFirst) return;

        ApplicationConfiguration.Initialize();
        AppIcon = Icon.ExtractAssociatedIcon(Environment.ProcessPath!);
        Application.Run(new TrayApplication());
    }
}
