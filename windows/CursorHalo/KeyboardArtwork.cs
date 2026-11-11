using System.Drawing.Drawing2D;
using System.Drawing.Imaging;

namespace CursorHalo;

internal static class KeyboardArtwork
{
    internal static Bitmap Render(string shortcut, uint dpi, int maximumWidth)
    {
        var scale = Math.Clamp(dpi, 96u, 768u) / 96f;
        using var font = new Font("Segoe UI", 22 * scale, FontStyle.Bold, GraphicsUnit.Pixel);
        using var measure = new Bitmap(1, 1);
        using var measureGraphics = Graphics.FromImage(measure);
        var measured = measureGraphics.MeasureString(shortcut, font);
        var width = Math.Max(1, Math.Min(maximumWidth, (int)Math.Ceiling(measured.Width + 40 * scale)));
        var height = (int)Math.Ceiling(58 * scale);
        var bitmap = new Bitmap(width, height, PixelFormat.Format32bppPArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.Clear(Color.Transparent);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var path = new GraphicsPath();
        var corner = Math.Min(18 * scale, Math.Min(width, height));
        path.AddArc(0, 0, corner, corner, 180, 90);
        path.AddArc(width - corner, 0, corner, corner, 270, 90);
        path.AddArc(width - corner, height - corner, corner, corner, 0, 90);
        path.AddArc(0, height - corner, corner, corner, 90, 90);
        path.CloseFigure();
        using var background = new SolidBrush(Color.FromArgb(230, 25, 28, 34));
        graphics.FillPath(background, path);
        using var format = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.EllipsisCharacter, FormatFlags = StringFormatFlags.NoWrap };
        graphics.DrawString(shortcut, font, Brushes.White, new RectangleF(10 * scale, 0, Math.Max(1, width - 20 * scale), height), format);
        return bitmap;
    }
}
