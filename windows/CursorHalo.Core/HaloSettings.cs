using System.Text.Json.Serialization;

namespace CursorHalo.Core;

public enum HaloStyle { Ring, Disc }
public enum HaloColor { Amber, Mint, Blue, Pink, White }
public enum ToggleShortcut { ControlAltH, ControlAltC, ControlShiftH }

public sealed record HaloSettings
{
    public bool IsEnabled { get; init; } = true;
    public HaloStyle Style { get; init; } = HaloStyle.Ring;
    public HaloColor Color { get; init; } = HaloColor.Amber;
    public double Diameter { get; init; } = 56;
    public double Opacity { get; init; } = .85;
    public double LineWidth { get; init; } = 3;
    public bool ShowsClicks { get; init; } = true;
    public ToggleShortcut Shortcut { get; init; } = ToggleShortcut.ControlAltH;

    public HaloSettings Sanitize() => this with
    {
        Style = Enum.IsDefined(Style) ? Style : HaloStyle.Ring,
        Color = Enum.IsDefined(Color) ? Color : HaloColor.Amber,
        Shortcut = Enum.IsDefined(Shortcut) ? Shortcut : ToggleShortcut.ControlAltH,
        Diameter = FiniteClamp(Diameter, 28, 120, 56),
        Opacity = FiniteClamp(Opacity, .2, 1, .85),
        LineWidth = FiniteClamp(LineWidth, 1, 8, 3)
    };

    public HaloSettings ResetAppearance() => new()
    {
        IsEnabled = IsEnabled,
        Shortcut = Shortcut
    };

    private static double FiniteClamp(double value, double min, double max, double fallback) =>
        double.IsFinite(value) ? Math.Clamp(value, min, max) : fallback;
}

public readonly record struct PixelPoint(int X, int Y);
public readonly record struct PixelFrame(int X, int Y, int Width, int Height);

public static class OverlayGeometry
{
    public static PixelFrame Centered(PixelPoint point, double diameter, uint dpi, bool pulse = false)
    {
        var safeDiameter = double.IsFinite(diameter) ? Math.Clamp(diameter, 28, 120) : 56;
        var scale = Math.Clamp(dpi, 96u, 768u) / 96.0;
        var side = (int)Math.Ceiling((safeDiameter * (pulse ? 2 : 1) + 16) * scale);
        return new PixelFrame(point.X - side / 2, point.Y - side / 2, side, side);
    }
}
