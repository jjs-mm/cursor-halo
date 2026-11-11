using CursorHalo.Core;

var tests = new (string Name, Action Run)[]
{
    ("Corrupt numeric and enum preferences have bounded fallbacks", () =>
    {
        var settings = new HaloSettings { Diameter = double.NaN, Opacity = double.PositiveInfinity, LineWidth = -200, Color = (HaloColor)99, Style = (HaloStyle)99, Shortcut = (ToggleShortcut)99 }.Sanitize();
        Check(settings.Diameter == 56 && settings.Opacity == .85 && settings.LineWidth == 1, "Numeric validation failed.");
        Check(settings.Color == HaloColor.Amber && settings.Style == HaloStyle.Ring && settings.Shortcut == ToggleShortcut.ControlAltH, "Enum validation failed.");
        Check((new HaloSettings { Diameter = 800, Opacity = -.2, LineWidth = 19 }).Sanitize() is { Diameter: 120, Opacity: .2, LineWidth: 8 }, "Range clamping failed.");
    }),
    ("Reset appearance preserves enabled state and shortcut", () =>
    {
        var reset = (new HaloSettings { IsEnabled = false, Shortcut = ToggleShortcut.ControlShiftH, ShowsKeyboardActivity = true, Diameter = 100, Color = HaloColor.Pink }).ResetAppearance();
        Check(!reset.IsEnabled && reset.Shortcut == ToggleShortcut.ControlShiftH && reset.ShowsKeyboardActivity, "Reset changed control settings.");
        Check(reset.Diameter == 56 && reset.Color == HaloColor.Amber, "Reset did not restore appearance.");
    }),
    ("Geometry keeps negative screen coordinates and scales with DPI", () =>
    {
        var normal = OverlayGeometry.Centered(new PixelPoint(-1920, -20), 56, 96);
        Check(normal.X == -1956 && normal.Y == -56 && normal.Width == 72, "Negative display coordinates were constrained.");
        var retina = OverlayGeometry.Centered(new PixelPoint(-1920, -20), 56, 192);
        Check(retina.Width == 144 && retina.X + retina.Width / 2 == -1920, "DPI scaling displaced the cursor.");
        Check(OverlayGeometry.Centered(default, double.NaN, uint.MaxValue).Width == 576, "Invalid geometry was not bounded.");
    }),
    ("Saved settings survive replacement and preserve all fields", () => WithDirectory(directory =>
    {
        var store = new SettingsStore(Path.Combine(directory, "settings.json"));
        Check(store.Load().IsFirstRun, "Missing file was not recognized.");
        var expected = new HaloSettings { IsEnabled = false, Color = HaloColor.Blue, Style = HaloStyle.Disc, Diameter = 83, Opacity = .42, LineWidth = 6.2, ShowsClicks = false, ShowsKeyboardActivity = true, Shortcut = ToggleShortcut.ControlAltC };
        Check(store.Save(new HaloSettings()) == null && store.Save(expected) == null, "Save failed.");
        Check(store.Load() is { Error: null, IsFirstRun: false } loaded && loaded.Settings == expected, "Round trip lost a preference.");
        Check(!Directory.EnumerateFiles(directory, "*.tmp").Any(), "Temporary files were left behind.");
    })),
    ("Keyboard activity is opt-in for new and existing settings", () => WithDirectory(directory =>
    {
        Check(!new HaloSettings().ShowsKeyboardActivity, "New installations unexpectedly observe shortcuts.");
        var path = Path.Combine(directory, "settings.json");
        File.WriteAllText(path, "{\"IsEnabled\":true,\"Color\":\"Blue\"}");
        var loaded = new SettingsStore(path).Load();
        Check(loaded.Error == null && !loaded.Settings.ShowsKeyboardActivity && loaded.Settings.Color == HaloColor.Blue,
            "Existing settings did not retain the opt-in default.");
    })),
    ("Shortcut display excludes ordinary typing, shift-only typing, AltGr and lone modifiers", () =>
    {
        Check(KeyboardShortcutFormatter.Format(0x41, KeyboardModifiers.None) == null, "Plain text was displayed.");
        Check(KeyboardShortcutFormatter.Format(0x41, KeyboardModifiers.Shift) == null, "Shift-only text was displayed.");
        Check(KeyboardShortcutFormatter.Format(0x45, KeyboardModifiers.Control | KeyboardModifiers.Alt | KeyboardModifiers.AltGr) == null,
            "AltGr text was treated as a shortcut.");
        foreach (uint key in new uint[] { 0x10, 0x11, 0x12, 0x5B, 0x5C, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5 })
            Check(KeyboardShortcutFormatter.Format(key, KeyboardModifiers.Control) == null, "A lone modifier was displayed.");
    }),
    ("Shortcut labels include modifiers and bounded key names", () =>
    {
        Check(KeyboardShortcutFormatter.Format(0x43, KeyboardModifiers.Control) == "Ctrl + C", "Copy shortcut is incorrect.");
        Check(KeyboardShortcutFormatter.Format(0x09, KeyboardModifiers.Alt | KeyboardModifiers.Shift) == "Alt + Shift + Tab", "Navigation chord is incorrect.");
        Check(KeyboardShortcutFormatter.Format(0x25, KeyboardModifiers.Windows) == "Win + ←", "Window shortcut is incorrect.");
        Check(KeyboardShortcutFormatter.Format(0x7B, KeyboardModifiers.Control) == "Ctrl + F12", "Function key is incorrect.");
        Check(KeyboardShortcutFormatter.Format(0xBA, KeyboardModifiers.Control, ";") == "Ctrl + ;", "Layout key was lost.");
        Check(KeyboardShortcutFormatter.Format(0xFF, KeyboardModifiers.Control) == null, "Unknown key was displayed.");
        Check(KeyboardShortcutFormatter.Format(0xBA, KeyboardModifiers.Control, "line\nbreak") == null, "Control character was displayed.");
        Check(KeyboardShortcutFormatter.Format(0xBA, KeyboardModifiers.Control, new string('x', 17)) == null, "Unbounded key name was displayed.");
    }),
    ("Malformed and oversized settings recover without rewriting source", () => WithDirectory(directory =>
    {
        var path = Path.Combine(directory, "settings.json");
        File.WriteAllText(path, "{broken");
        var store = new SettingsStore(path);
        Check(store.Load().Error != null && store.Load().Settings == new HaloSettings(), "Malformed JSON did not recover.");
        Check(File.ReadAllText(path) == "{broken", "Loading rewrote source data.");
        File.WriteAllText(path, "null");
        Check(store.Load().Error != null && store.Load().Settings == new HaloSettings(), "Null JSON did not recover.");
        File.WriteAllText(path, new string(' ', 70_000));
        Check(store.Load().Error != null, "Oversized input was accepted.");
    })),
    ("Write failure returns an actionable error and cleans temporary files", () => WithDirectory(directory =>
    {
        var destination = Path.Combine(directory, "settings.json");
        Directory.CreateDirectory(destination);
        var failure = new SettingsStore(destination).Save(new HaloSettings());
        Check(failure?.Contains("this session") == true, "Storage failure was not surfaced.");
        Check(Directory.Exists(destination), "Failed save removed the existing destination.");
        Check(!Directory.EnumerateFiles(directory, "*.tmp").Any(), "Failed save left a temporary file.");
    }))
};

var failed = 0;
foreach (var test in tests)
{
    try { test.Run(); Console.WriteLine($"PASS {test.Name}"); }
    catch (Exception error) { failed++; Console.Error.WriteLine($"FAIL {test.Name}: {error}"); }
}
Console.WriteLine($"{tests.Length - failed}/{tests.Length} checks passed.");
return failed == 0 ? 0 : 1;

static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
static void WithDirectory(Action<string> run)
{
    var directory = Path.Combine(Path.GetTempPath(), "cursor-halo-tests-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(directory);
    try { run(directory); }
    finally { Directory.Delete(directory, recursive: true); }
}
