using CursorHalo.Core;
using Microsoft.Win32;

namespace CursorHalo;

internal sealed class TrayApplication : ApplicationContext
{
    private readonly MessageWindow receiver = new();
    private readonly StartupRegistration startup = new();
    private readonly SettingsStore store;
    private readonly OverlayController overlay;
    private readonly NotifyIcon tray;
    private readonly ContextMenuStrip menu = new();
    private readonly ToolStripMenuItem enabledItem = new("Highlight cursor");
    private readonly ToolStripMenuItem loginItem = new("Launch at login");
    private readonly Icon icon = HaloArtwork.CreateIcon();
    private SettingsForm? settingsForm;
    private HaloSettings settings;
    private bool sessionAvailable = true;
    private bool suspended;
    private bool cleaned;
    private string? storageError;
    private string? shortcutError;
    private string? overlayError;

    internal TrayApplication(bool reveal)
    {
        store = new SettingsStore(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CursorHalo", "settings.json"));
        var loaded = store.Load();
        settings = loaded.Settings;
        storageError = loaded.Error;
        if (loaded.IsFirstRun) storageError = store.Save(settings);
        overlay = new OverlayController(receiver.Handle);
        overlay.Failed += message => { overlayError = message; ShowError(); };
        receiver.PointerUpdated += overlay.HandlePointerUpdate;
        receiver.ToggleRequested += Toggle;
        receiver.SettingsRequested += ShowSettings;
        var settingsItem = new ToolStripMenuItem("Settings…", null, (_, _) => ShowSettings());
        enabledItem.Click += (_, _) => Toggle();
        loginItem.Click += (_, _) =>
        {
            var state = startup.Read();
            var failure = startup.SetEnabled(!state.IsRegistered);
            settingsForm?.RefreshStartup();
            if (failure != null) { ShowSettings(); settingsForm!.ShowStartupError(failure); }
        };
        menu.Items.AddRange([settingsItem, enabledItem, loginItem, new ToolStripSeparator(), new ToolStripMenuItem("Quit", null, (_, _) => ExitThread())]);
        menu.Opening += (_, _) =>
        {
            enabledItem.Checked = settings.IsEnabled;
            var state = startup.Read();
            loginItem.Checked = state.IsRegistered;
            loginItem.Enabled = state.Error == null;
        };
        tray = new NotifyIcon { Text = "Cursor Halo", Icon = icon, ContextMenuStrip = menu, Visible = true };
        tray.DoubleClick += (_, _) => ShowSettings();
        SystemEvents.SessionSwitch += SessionChanged;
        SystemEvents.PowerModeChanged += PowerChanged;
        SystemEvents.DisplaySettingsChanged += DisplaysChanged;
        Apply();
        if (reveal || loaded.IsFirstRun || storageError != null || shortcutError != null)
            receiver.Post(ShowSettings);
    }

    private void Toggle() => Change(settings with { IsEnabled = !settings.IsEnabled });

    private void Change(HaloSettings value)
    {
        settings = value.Sanitize();
        overlayError = null;
        Apply();
        // Save the confirmed shortcut, including rollback after a conflict.
        storageError = store.Save(settings);
        ShowError();
    }

    private void Apply()
    {
        shortcutError = receiver.RegisterShortcut(settings.Shortcut);
        if (shortcutError != null && receiver.RegisteredShortcut is { } previous)
            settings = settings with { Shortcut = previous };
        overlay.Update(settings, sessionAvailable && !suspended);
        tray.Text = settings.IsEnabled ? "Cursor Halo · On" : "Cursor Halo · Paused";
        enabledItem.Checked = settings.IsEnabled;
        settingsForm?.UpdateSettings(settings);
        ShowError();
    }

    private void ShowSettings()
    {
        if (cleaned) return;
        settingsForm ??= new SettingsForm(settings, Change, startup.Read, startup.SetEnabled) { Icon = icon };
        settingsForm.UpdateSettings(settings);
        ShowError();
        settingsForm.Reveal();
    }

    private void ShowError()
    {
        settingsForm?.ShowError(string.Join("\n", new[] { storageError, shortcutError, overlayError }.Where(value => !string.IsNullOrWhiteSpace(value))));
    }

    private void SessionChanged(object sender, SessionSwitchEventArgs args) => receiver.Post(() =>
    {
        if (args.Reason is SessionSwitchReason.SessionLock or SessionSwitchReason.SessionLogoff or SessionSwitchReason.RemoteDisconnect or SessionSwitchReason.ConsoleDisconnect)
            sessionAvailable = false;
        else if (args.Reason is SessionSwitchReason.SessionUnlock or SessionSwitchReason.SessionLogon or SessionSwitchReason.RemoteConnect or SessionSwitchReason.ConsoleConnect)
            sessionAvailable = true;
        overlay.Update(settings, sessionAvailable && !suspended);
    });

    private void PowerChanged(object sender, PowerModeChangedEventArgs args) => receiver.Post(() =>
    {
        if (args.Mode == PowerModes.Suspend) suspended = true;
        else if (args.Mode == PowerModes.Resume) suspended = false;
        overlay.Update(settings, sessionAvailable && !suspended);
    });

    private void DisplaysChanged(object? sender, EventArgs args) => receiver.Post(overlay.RefreshDisplays);

    protected override void Dispose(bool disposing)
    {
        if (disposing && !cleaned)
        {
            cleaned = true;
            SystemEvents.SessionSwitch -= SessionChanged;
            SystemEvents.PowerModeChanged -= PowerChanged;
            SystemEvents.DisplaySettingsChanged -= DisplaysChanged;
            overlay.Dispose();
            receiver.Dispose();
            tray.Visible = false;
            tray.Dispose();
            settingsForm?.Dispose();
            menu.Dispose();
            icon.Dispose();
        }
        base.Dispose(disposing);
    }
}
