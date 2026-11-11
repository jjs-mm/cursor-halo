using System.Security.Principal;

namespace CursorHalo;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        if (args.Contains("--smoke-test", StringComparer.Ordinal)) return SmokeTest.Run(args);

        var identity = WindowsIdentity.GetCurrent().User?.Value ?? Environment.UserName;
        using var mutex = new Mutex(true, @"Local\CursorHalo." + identity, out var firstInstance);
        if (!firstInstance)
        {
            // A second launch is a request to reveal the existing settings. Wait
            // briefly only for the first process to create its receiver window.
            for (var attempt = 0; attempt < 20; attempt++)
            {
                var window = Native.FindWindow(null, MessageWindow.WindowTitle);
                if (window != 0) { Native.PostMessage(window, MessageWindow.RevealMessage, 0, 0); return 0; }
                Thread.Sleep(50);
            }
            return 0;
        }
        try
        {
            using var context = new TrayApplication(args.Contains("--show-settings", StringComparer.Ordinal));
            Application.Run(context);
            return 0;
        }
        catch (Exception error)
        {
            MessageBox.Show($"Cursor Halo could not start.\n\n{error.Message}", "Cursor Halo", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
        finally { mutex.ReleaseMutex(); }
    }
}
