using CursorHalo.Core;
using System.Diagnostics;

namespace CursorHalo;

internal sealed class OverlayController : IDisposable
{
    private sealed record Pulse(OverlayWindow Window, PixelPoint Point, uint Dpi, bool Secondary, bool ReducedMotion, long Started);
    private readonly nint receiver;
    private readonly OverlayWindow halo = new();
    private readonly List<Pulse> pulses = [];
    private readonly System.Windows.Forms.Timer animation = new() { Interval = 16 };
    private MouseEventSource? mouse;
    private HaloSettings settings = new();
    private uint haloDpi;
    private bool disposed;
    private bool active;
    internal event Action<string>? Failed;

    internal OverlayController(nint receiver)
    {
        this.receiver = receiver;
        animation.Tick += (_, _) => Animate();
    }

    internal void Update(HaloSettings value, bool sessionAvailable)
    {
        settings = value.Sanitize();
        active = settings.IsEnabled && sessionAvailable && !disposed;
        if (!active) { Suspend(); return; }
        try
        {
            mouse ??= new MouseEventSource(receiver);
            haloDpi = 0; // Appearance changes must redraw even at the same DPI.
            if (!settings.ShowsClicks) ClearPulses();
            if (Native.GetCursorPos(out var point)) Move(new PixelPoint(point.X, point.Y));
        }
        catch (Exception error) { ReportFailure(error); }
    }

    internal void HandlePointerUpdate()
    {
        if (!active || mouse == null) return;
        var batch = mouse.Drain();
        try
        {
            if (batch.Position is { } point) Move(point);
            if (settings.ShowsClicks)
                foreach (var click in batch.Clicks) AddPulse(click);
        }
        catch (Exception error) { ReportFailure(error); }
    }

    internal void RefreshDisplays()
    {
        ClearPulses();
        Update(settings, active);
    }

    private void Move(PixelPoint point)
    {
        var dpi = halo.PositionAndReadDpi(point);
        if (haloDpi == dpi) return; // Moving the window reuses its compositor bitmap.
        using var image = HaloArtwork.Render(settings, dpi);
        halo.Present(image, point);
        haloDpi = dpi;
    }

    private void AddPulse(ClickEvent click)
    {
        if (pulses.Count == 8) { pulses[0].Window.Dispose(); pulses.RemoveAt(0); }
        var window = new OverlayWindow();
        try
        {
            var dpi = window.PositionAndReadDpi(click.Point);
            var reduced = Native.SystemParametersInfo(0x1042, 0, out var enabled, 0) && !enabled;
            var pulse = new Pulse(window, click.Point, dpi, click.Secondary, reduced, Stopwatch.GetTimestamp());
            using var image = HaloArtwork.Render(settings, dpi, true, click.Secondary, 0, reduced);
            window.Present(image, click.Point);
            pulses.Add(pulse);
            animation.Start();
        }
        catch { window.Dispose(); throw; }
    }

    private void Animate()
    {
        try
        {
            for (var index = pulses.Count - 1; index >= 0; index--)
            {
                var pulse = pulses[index];
                var progress = Stopwatch.GetElapsedTime(pulse.Started).TotalSeconds / .45;
                if (progress >= 1)
                {
                    pulse.Window.Dispose();
                    pulses.RemoveAt(index);
                }
                else if (!pulse.ReducedMotion)
                {
                    using var image = HaloArtwork.Render(settings, pulse.Dpi, true, pulse.Secondary, progress);
                    pulse.Window.Present(image, pulse.Point);
                }
            }
            if (pulses.Count == 0) animation.Stop();
        }
        catch (Exception error) { ReportFailure(error); }
    }

    private void ReportFailure(Exception error)
    {
        active = false;
        Suspend();
        Failed?.Invoke($"The halo paused because Windows could not update it. Toggle it off and on to retry. {error.Message}");
    }

    private void ClearPulses()
    {
        animation.Stop();
        foreach (var pulse in pulses) pulse.Window.Dispose();
        pulses.Clear();
    }

    private void Suspend()
    {
        mouse?.Dispose();
        mouse = null;
        halo.Conceal();
        haloDpi = 0;
        ClearPulses();
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        active = false;
        Suspend();
        animation.Dispose();
        halo.Dispose();
    }
}
