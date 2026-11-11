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
        var reset = (new HaloSettings { IsEnabled = false, Shortcut = ToggleShortcut.ControlShiftH, Diameter = 100, Color = HaloColor.Pink }).ResetAppearance();
        Check(!reset.IsEnabled && reset.Shortcut == ToggleShortcut.ControlShiftH, "Reset changed control settings.");
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
        var expected = new HaloSettings { IsEnabled = false, Color = HaloColor.Blue, Style = HaloStyle.Disc, Diameter = 83, Opacity = .42, LineWidth = 6.2, ShowsClicks = false, Shortcut = ToggleShortcut.ControlAltC };
        Check(store.Save(new HaloSettings()) == null && store.Save(expected) == null, "Save failed.");
        Check(store.Load() is { Error: null, IsFirstRun: false } loaded && loaded.Settings == expected, "Round trip lost a preference.");
        Check(!Directory.EnumerateFiles(directory, "*.tmp").Any(), "Temporary files were left behind.");
    })),
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
