using CursorHalo.Core;
using System.Drawing.Imaging;
using System.Text.Json;

namespace CursorHalo;

internal static class SmokeTest
{
    internal static int Run(string[] args)
    {
        var checks = new List<string>();
        string? error = null;
        try
        {
            using var receiver = new MessageWindow();
            var before = Native.GetForegroundWindow();
            nint overlayHandle;
            using (var overlay = new OverlayWindow())
            {
                overlayHandle = overlay.Handle;
                var point = new PixelPoint(-30, 50);
                var dpi = overlay.PositionAndReadDpi(point);
                using var image = HaloArtwork.Render(new HaloSettings(), dpi);
                overlay.Present(image, point);
                var styles = Native.GetWindowLongPtr(overlay.Handle, -20).ToInt64();
                Require((styles & OverlayWindow.RequiredStyles) == OverlayWindow.RequiredStyles, "Overlay extended styles are incorrect.");
                Require(Native.IsWindowVisible(overlay.Handle), "Overlay did not become visible.");
                Require(Native.GetForegroundWindow() == before, "Overlay took keyboard focus.");
                checks.Add("Transparent, click-through, nonactivating native overlay rendered at negative coordinates.");
                overlay.Conceal();
                Require(!Native.IsWindowVisible(overlay.Handle), "Overlay did not hide.");
            }
            Require(!Native.IsWindow(overlayHandle), "Disposed overlay window still exists.");
            checks.Add("Overlay hides and native window is destroyed on disposal.");
            string? hotKeyError = null;
            foreach (var shortcut in Enum.GetValues<ToggleShortcut>())
            {
                hotKeyError = receiver.RegisterShortcut(shortcut);
                if (hotKeyError == null) break;
            }
            Require(hotKeyError == null, hotKeyError ?? "No hotkey available.");
            checks.Add("A global toggle hotkey was registered.");
            var originalShortcut = receiver.RegisteredShortcut!.Value;
            var originalId = receiver.ActiveHotKeyId;
            using (var reserved = new MessageWindow())
            {
                ToggleShortcut? reservedShortcut = null;
                foreach (var candidate in Enum.GetValues<ToggleShortcut>().Where(value => value != originalShortcut))
                {
                    if (reserved.RegisterShortcut(candidate) == null) { reservedShortcut = candidate; break; }
                }
                Require(reservedShortcut != null, "A second shortcut is required to test conflict recovery.");
                Require(receiver.RegisterShortcut(reservedShortcut!.Value) != null, "Conflicting shortcut unexpectedly registered.");
                Require(receiver.RegisteredShortcut == originalShortcut && receiver.ActiveHotKeyId == originalId,
                    "A failed shortcut replacement lost the prior registration.");
                var toggles = 0;
                receiver.ToggleRequested += () => toggles++;
                Native.PostMessage(receiver.Handle, Native.WmHotKey, originalId == 1 ? 2 : 1, 0);
                Native.PostMessage(receiver.Handle, Native.WmHotKey, originalId, 0);
                Application.DoEvents();
                Require(toggles == 1, "Only the active hotkey ID should invoke the toggle.");
            }
            checks.Add("Shortcut conflict preserves the active registration and ignores a stale hotkey ID.");
            var mouse = new MouseEventSource(receiver.Handle);
            using (mouse) { _ = mouse.Drain(); }
            Require(!mouse.IsRunning, "The mouse observer thread remained alive after disposal.");
            checks.Add("Dedicated mouse observer installed and disposed without generating input.");
            var keyboard = new KeyboardEventSource(receiver.Handle);
            using (keyboard) { Require(keyboard.Drain() == null, "Keyboard observer unexpectedly retained input."); }
            Require(!keyboard.IsRunning && keyboard.Drain() == null, "Keyboard observer retained activity after disposal.");
            checks.Add("Dedicated shortcut observer installed and disposed without generating input or retaining history.");
            using (var controller = new OverlayController(receiver.Handle))
            {
                controller.Update(new HaloSettings(), true);
                Require(!controller.IsKeyboardMonitoring, "Default settings observed keyboard shortcuts.");
                controller.Update(new HaloSettings { ShowsKeyboardActivity = true }, true);
                Require(controller.IsKeyboardMonitoring, "Opting in did not start keyboard observation.");
                var focus = Native.GetForegroundWindow();
                var shortcut = new KeyboardShortcut(0x43, KeyboardModifiers.Control, Native.GetKeyboardLayout(0));
                controller.HandleKeyboardShortcut(shortcut);
                Require(controller.IsKeyboardBadgeVisible && Native.GetForegroundWindow() == focus, "Shortcut feedback was missing or took focus.");
                var expiry = System.Diagnostics.Stopwatch.StartNew();
                while (controller.IsKeyboardBadgeVisible && expiry.Elapsed.TotalSeconds < 3)
                {
                    Application.DoEvents();
                    Thread.Sleep(25);
                }
                Require(!controller.IsKeyboardBadgeVisible, "Shortcut feedback did not expire.");
                controller.HandleKeyboardShortcut(shortcut);
                controller.Update(new HaloSettings { ShowsKeyboardActivity = true, IsEnabled = false }, true);
                Require(!controller.IsKeyboardMonitoring && !controller.IsKeyboardBadgeVisible, "Pausing did not stop and clear keyboard activity.");
                controller.Update(new HaloSettings { ShowsKeyboardActivity = true }, false);
                Require(!controller.IsKeyboardMonitoring, "An unavailable session observed keyboard shortcuts.");
                controller.Update(new HaloSettings { ShowsKeyboardActivity = true }, true);
                controller.Update(new HaloSettings(), true);
                Require(!controller.IsKeyboardMonitoring, "Opting out did not stop keyboard observation.");
            }
            checks.Add("Keyboard feedback expires without taking focus; observation follows opt-in, pause, session availability, and opt-out.");
            using (var badge = new OverlayWindow())
            {
                var focus = Native.GetForegroundWindow();
                var point = new PixelPoint(250, 250);
                var dpi = badge.PositionAndReadDpi(point);
                using var image = KeyboardArtwork.Render("Ctrl + Shift + C", dpi, 600);
                badge.Present(image, point);
                Require(Native.IsWindowVisible(badge.Handle) && Native.GetForegroundWindow() == focus,
                    "Keyboard badge was invisible or took keyboard focus.");
                var styles = Native.GetWindowLongPtr(badge.Handle, -20).ToInt64();
                Require((styles & OverlayWindow.RequiredStyles) == OverlayWindow.RequiredStyles, "Keyboard badge blocked input.");
            }
            checks.Add("Keyboard shortcut artwork renders in a click-through, nonactivating overlay.");
            receiver.Dispose();
            using (var replacement = new MessageWindow())
                Require(replacement.RegisterShortcut(originalShortcut) == null, "Disposed receiver retained its global hotkey.");
            checks.Add("Global hotkey is available again after receiver disposal.");
            using var form = new SettingsForm(new HaloSettings(), _ => { }, () => new StartupState(false, false, null), _ => null);
            form.Show();
            Application.DoEvents();
            Require(form.Controls.Count > 0, "Settings did not create controls.");
            if (Argument(args, "--screenshot") is { } screenshot)
            {
                using var bitmap = new Bitmap(form.Width, form.Height);
                form.DrawToBitmap(bitmap, new Rectangle(0, 0, bitmap.Width, bitmap.Height));
                Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(screenshot))!);
                bitmap.Save(screenshot, ImageFormat.Png);
                checks.Add("Settings screenshot written from the isolated smoke form.");
            }
            checks.Add("Settings UI constructed with fake startup callbacks and no preference storage.");
        }
        catch (Exception exception) { error = exception.ToString(); }
        var result = JsonSerializer.Serialize(new { success = error == null, checks, error }, new JsonSerializerOptions { WriteIndented = true });
        Console.WriteLine(result);
        if (Argument(args, "--smoke-test-output") is { } output)
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(output))!);
                File.WriteAllText(output, result);
            }
            catch (Exception exception) { Console.Error.WriteLine(exception); return 1; }
        }
        return error == null ? 0 : 1;
    }

    private static string? Argument(string[] args, string name)
    {
        var index = Array.IndexOf(args, name);
        return index >= 0 && index + 1 < args.Length ? args[index + 1] : null;
    }

    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
