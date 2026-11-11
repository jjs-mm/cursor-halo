using CursorHalo.Core;
using System.ComponentModel;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

namespace CursorHalo;

internal sealed class OverlayWindow : Form
{
    internal const int RequiredStyles = Native.WsExLayered | Native.WsExTransparent | Native.WsExNoActivate | Native.WsExToolWindow;
    internal OverlayWindow()
    {
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        AutoScaleMode = AutoScaleMode.None;
        StartPosition = FormStartPosition.Manual;
        Text = "Cursor Halo overlay";
        _ = Handle;
    }

    protected override bool ShowWithoutActivation => true;
    protected override CreateParams CreateParams
    {
        get { var value = base.CreateParams; value.ExStyle |= RequiredStyles; return value; }
    }

    protected override void WndProc(ref System.Windows.Forms.Message message)
    {
        if (message.Msg == 0x84) { message.Result = new nint(-1); return; } // HTTRANSPARENT
        if (message.Msg == 0x21) { message.Result = new nint(3); return; } // MA_NOACTIVATE
        if (message.Msg == 0x2E0) { message.Result = 0; return; } // The renderer owns DPI-sized pixel geometry.
        base.WndProc(ref message);
    }

    internal uint PositionAndReadDpi(PixelPoint point)
    {
        if (!Native.SetWindowPos(Handle, 0, point.X - Width / 2, point.Y - Height / 2, 0, 0,
            Native.SwpNoActivate | Native.SwpNoSize | 0x4))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Couldn’t position the cursor overlay.");
        return Math.Clamp(Native.GetDpiForWindow(Handle), 96u, 768u);
    }

    internal void Present(Bitmap bitmap, PixelPoint point)
    {
        nint screen = 0, memory = 0, image = 0, old = 0;
        try
        {
            screen = Native.GetDC(0);
            memory = Native.CreateCompatibleDC(screen);
            if (screen == 0 || memory == 0) throw new Win32Exception("Couldn’t create an overlay drawing surface.");
            image = bitmap.GetHbitmap(Color.FromArgb(0));
            old = Native.SelectObject(memory, image);
            var size = new Native.Size(bitmap.Width, bitmap.Height);
            var origin = new Native.Point(point.X - bitmap.Width / 2, point.Y - bitmap.Height / 2);
            var source = new Native.Point(0, 0);
            var blend = new Native.Blend { Operation = 0, Flags = 0, Alpha = 255, Format = 1 };
            if (!Native.UpdateLayeredWindow(Handle, screen, ref origin, ref size, memory, ref source, 0, ref blend, 2))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Couldn’t render the cursor overlay.");
            if (!Native.SetWindowPos(Handle, Native.HwndTopmost, 0, 0, 0, 0,
                Native.SwpNoActivate | Native.SwpNoMove | Native.SwpNoSize | Native.SwpShowWindow))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Couldn’t show the cursor overlay.");
        }
        finally
        {
            if (old != 0 && memory != 0) Native.SelectObject(memory, old);
            if (image != 0) Native.DeleteObject(image);
            if (memory != 0) Native.DeleteDC(memory);
            if (screen != 0) Native.ReleaseDC(0, screen);
        }
    }

    internal void Conceal() => Native.ShowWindow(Handle, 0);
}

internal static class HaloArtwork
{
    internal static Color ColorFor(HaloColor color) => color switch
    {
        HaloColor.Mint => Color.FromArgb(64, 232, 184),
        HaloColor.Blue => Color.FromArgb(71, 171, 255),
        HaloColor.Pink => Color.FromArgb(255, 99, 163),
        HaloColor.White => Color.White,
        _ => Color.FromArgb(255, 191, 46)
    };

    internal static Bitmap Render(HaloSettings settings, uint dpi, bool pulse = false, bool secondary = false, double progress = 0, bool reduceMotion = false)
    {
        var frame = OverlayGeometry.Centered(default, settings.Diameter, dpi, pulse);
        var bitmap = new Bitmap(frame.Width, frame.Height, PixelFormat.Format32bppPArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.Transparent);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        var scale = dpi / 96f;
        var color = secondary ? (settings.Color == HaloColor.Pink ? Color.Cyan : Color.DeepPink) : ColorFor(settings.Color);
        var opacity = settings.Opacity;
        var diameter = (float)settings.Diameter * scale;
        var width = (float)settings.LineWidth * scale;
        if (pulse)
        {
            var eased = 1 - Math.Pow(1 - progress, 3);
            diameter = (frame.Width - 12 * scale) * (float)(reduceMotion ? .6 : .25 + .75 * eased);
            width = (secondary ? 3.5f : 2.5f) * scale;
            opacity *= reduceMotion ? .9 : .9 * (1 - progress);
        }
        var rectangle = new RectangleF((frame.Width - diameter + width) / 2, (frame.Height - diameter + width) / 2,
            diameter - width, diameter - width);
        if (!pulse && settings.Style == HaloStyle.Disc)
        {
            using var fill = new SolidBrush(Color.FromArgb((int)(opacity * .24 * 255), color));
            graphics.FillEllipse(fill, rectangle);
        }
        using var outline = new Pen(Color.FromArgb((int)(opacity * .65 * 255), Color.Black), width + 2 * scale);
        using var ring = new Pen(Color.FromArgb((int)(opacity * 255), color), width);
        graphics.DrawEllipse(outline, rectangle);
        graphics.DrawEllipse(ring, rectangle);
        return bitmap;
    }

    internal static Icon CreateIcon()
    {
        using var bitmap = new Bitmap(32, 32, PixelFormat.Format32bppPArgb);
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using var outline = new Pen(Color.FromArgb(30, 35, 42), 7);
            using var ring = new Pen(ColorFor(HaloColor.Amber), 4);
            graphics.DrawEllipse(outline, 5, 5, 22, 22);
            graphics.DrawEllipse(ring, 5, 5, 22, 22);
            graphics.FillPolygon(Brushes.White, [new Point(13, 9), new Point(13, 24), new Point(17, 20), new Point(23, 20)]);
        }
        var handle = bitmap.GetHicon();
        try { using var borrowed = Icon.FromHandle(handle); return (Icon)borrowed.Clone(); }
        finally { Native.DestroyIcon(handle); }
    }
}
