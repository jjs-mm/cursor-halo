using CursorHalo.Core;
using System.Drawing.Drawing2D;

namespace CursorHalo;

internal sealed class SettingsForm : Form
{
    private HaloSettings settings;
    private readonly Action<HaloSettings> change;
    private readonly Func<StartupState> readStartup;
    private readonly Func<bool, string?> setStartup;
    private readonly CheckBox enabled = new() { Text = "Highlight cursor", AutoSize = true };
    private readonly CheckBox clicks = new() { Text = "Show click feedback", AutoSize = true };
    private readonly CheckBox keyboard = new() { Text = "Show keyboard activity", AutoSize = true };
    private readonly CheckBox login = new() { Text = "Launch at login", AutoSize = true };
    private readonly ComboBox style = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox color = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly ComboBox shortcut = new() { DropDownStyle = ComboBoxStyle.DropDownList };
    private readonly TrackBar diameter = Slider(28, 120);
    private readonly TrackBar opacity = Slider(20, 100);
    private readonly TrackBar stroke = Slider(10, 80);
    private readonly Label diameterValue = new() { AutoSize = true };
    private readonly Label opacityValue = new() { AutoSize = true };
    private readonly Label strokeValue = new() { AutoSize = true };
    private readonly Label error = new() { AutoSize = true, ForeColor = Color.FromArgb(170, 50, 30), MaximumSize = new Size(350, 0) };
    private readonly Panel preview = new() { Height = 130, BackColor = Color.FromArgb(245, 246, 248), Dock = DockStyle.Fill };
    private bool refreshing;
    private string? appError;
    private string? startupError;

    internal SettingsForm(HaloSettings settings, Action<HaloSettings> change, Func<StartupState> readStartup, Func<bool, string?> setStartup)
    {
        this.settings = settings;
        this.change = change;
        this.readStartup = readStartup;
        this.setStartup = setStartup;
        Text = "Cursor Halo";
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(400, 680);
        MinimumSize = new Size(370, 430);
        StartPosition = FormStartPosition.CenterScreen;
        Font = new Font("Segoe UI", 10);
        FormBorderStyle = FormBorderStyle.Sizable;
        MaximizeBox = false;
        var scroll = new Panel { Dock = DockStyle.Fill, AutoScroll = true };
        var layout = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 1, Padding = new Padding(22) };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        Controls.Add(scroll);
        scroll.Controls.Add(layout);
        Add(layout, new Label { Text = "Cursor Halo", Font = new Font(Font.FontFamily, 20, FontStyle.Bold), AutoSize = true });
        Add(layout, new Label { Text = "A little easier to follow.", AutoSize = true, ForeColor = SystemColors.GrayText });
        Add(layout, enabled);
        Add(layout, preview, 12);
        style.Items.AddRange(["Ring", "Soft disc"]);
        color.Items.AddRange(["Amber", "Mint", "Blue", "Pink", "White"]);
        shortcut.Items.AddRange(["Ctrl + Alt + H", "Ctrl + Alt + C", "Ctrl + Shift + H"]);
        Add(layout, Row("Style", style));
        Add(layout, Row("Color", color));
        Add(layout, SliderRow("Size", diameter, diameterValue));
        Add(layout, SliderRow("Opacity", opacity, opacityValue));
        Add(layout, SliderRow("Stroke", stroke, strokeValue));
        Add(layout, clicks);
        Add(layout, new Label { Text = "Right-clicks use a contrasting color. Windows animation settings are respected.", AutoSize = true, MaximumSize = new Size(350, 0), ForeColor = SystemColors.GrayText, Font = new Font(Font.FontFamily, 9) });
        Add(layout, keyboard);
        Add(layout, new Label { Text = "Briefly displays Ctrl, Alt, or Win shortcuts. Ordinary typing and AltGr are excluded. Nothing is saved.", AutoSize = true, MaximumSize = new Size(350, 0), ForeColor = SystemColors.GrayText, Font = new Font(Font.FontFamily, 9) });
        Add(layout, Row("Toggle shortcut", shortcut));
        Add(layout, login);
        Add(layout, new Label { Text = "Windows Startup Apps can also control automatic launch.", AutoSize = true, MaximumSize = new Size(350, 0), ForeColor = SystemColors.GrayText, Font = new Font(Font.FontFamily, 9) });
        Add(layout, error);
        Add(layout, new Label { Text = "For recordings, share your whole display so the halo is included.", AutoSize = true, MaximumSize = new Size(350, 0), ForeColor = SystemColors.GrayText, Font = new Font(Font.FontFamily, 9) });
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        var reset = new Button { Text = "Reset appearance", AutoSize = true };
        reset.Click += (_, _) => Commit(this.settings.ResetAppearance());
        var close = new Button { Text = "Done", AutoSize = true };
        close.Click += (_, _) => Hide();
        buttons.Controls.AddRange([reset, close]);
        Add(layout, buttons, 12);
        enabled.CheckedChanged += (_, _) => { if (!refreshing) Commit(this.settings with { IsEnabled = enabled.Checked }); };
        clicks.CheckedChanged += (_, _) => { if (!refreshing) Commit(this.settings with { ShowsClicks = clicks.Checked }); };
        keyboard.CheckedChanged += (_, _) => { if (!refreshing) Commit(this.settings with { ShowsKeyboardActivity = keyboard.Checked }); };
        style.SelectedIndexChanged += (_, _) => { if (!refreshing) Commit(this.settings with { Style = (HaloStyle)style.SelectedIndex }); };
        color.SelectedIndexChanged += (_, _) => { if (!refreshing) Commit(this.settings with { Color = (HaloColor)color.SelectedIndex }); };
        shortcut.SelectedIndexChanged += (_, _) => { if (!refreshing) Commit(this.settings with { Shortcut = (ToggleShortcut)shortcut.SelectedIndex }); };
        diameter.Scroll += (_, _) => Commit(this.settings with { Diameter = diameter.Value });
        opacity.Scroll += (_, _) => Commit(this.settings with { Opacity = opacity.Value / 100.0 });
        stroke.Scroll += (_, _) => Commit(this.settings with { LineWidth = stroke.Value / 10.0 });
        login.CheckedChanged += (_, _) =>
        {
            if (refreshing) return;
            var failure = setStartup(login.Checked);
            RefreshStartup();
            if (failure != null) ShowStartupError(failure);
        };
        preview.Paint += DrawPreview;
        Activated += (_, _) => RefreshStartup();
        FormClosing += (_, args) =>
        {
            if (args.CloseReason == CloseReason.UserClosing) { args.Cancel = true; Hide(); }
        };
        UpdateSettings(settings);
        RefreshStartup();
        Shown += (_, _) =>
        {
            var area = Screen.FromControl(this).WorkingArea;
            if (Height > area.Height - 40) Height = Math.Max(MinimumSize.Height, area.Height - 40);
        };
    }

    internal void UpdateSettings(HaloSettings value)
    {
        settings = value.Sanitize();
        refreshing = true;
        enabled.Checked = settings.IsEnabled;
        clicks.Checked = settings.ShowsClicks;
        keyboard.Checked = settings.ShowsKeyboardActivity;
        style.SelectedIndex = (int)settings.Style;
        color.SelectedIndex = (int)settings.Color;
        shortcut.SelectedIndex = (int)settings.Shortcut;
        diameter.Value = (int)Math.Round(settings.Diameter);
        opacity.Value = (int)Math.Round(settings.Opacity * 100);
        stroke.Value = (int)Math.Round(settings.LineWidth * 10);
        diameterValue.Text = $"{diameter.Value} pt";
        opacityValue.Text = $"{opacity.Value}%";
        strokeValue.Text = $"{settings.LineWidth:0.0} pt";
        refreshing = false;
        preview.Invalidate();
    }

    internal void ShowError(string? message)
    {
        appError = message;
        UpdateErrors();
    }

    internal void ShowStartupError(string? message) { startupError = message; UpdateErrors(); }

    private void UpdateErrors()
    {
        error.Text = string.Join("\n", new[] { appError, startupError }.Where(value => !string.IsNullOrWhiteSpace(value)));
        error.Visible = error.Text.Length > 0;
    }

    internal void Reveal()
    {
        RefreshStartup();
        Show();
        if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
        BringToFront();
        Activate();
    }

    private void Commit(HaloSettings value)
    {
        UpdateSettings(value);
        change(settings);
    }

    internal void RefreshStartup()
    {
        var state = readStartup();
        refreshing = true;
        login.Checked = state.IsRegistered;
        refreshing = false;
        ShowStartupError(state.Error);
    }

    private void DrawPreview(object? sender, PaintEventArgs args)
    {
        args.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
        using var bitmap = HaloArtwork.Render(settings, (uint)DeviceDpi);
        args.Graphics.DrawImageUnscaled(bitmap, (preview.Width - bitmap.Width) / 2, (preview.Height - bitmap.Height) / 2);
        var scale = DeviceDpi / 96f;
        var center = new PointF(preview.Width / 2f, preview.Height / 2f);
        PointF[] points = [center, new(center.X, center.Y + 22 * scale), new(center.X + 6 * scale, center.Y + 16 * scale), new(center.X + 14 * scale, center.Y + 16 * scale)];
        args.Graphics.FillPolygon(Brushes.White, points);
        args.Graphics.DrawPolygon(Pens.Black, points);
    }

    private static TrackBar Slider(int min, int max) => new() { Minimum = min, Maximum = max, TickStyle = TickStyle.None, AutoSize = false, Height = 30, Dock = DockStyle.Fill };
    private static Control Row(string label, Control control)
    {
        var row = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Dock = DockStyle.Fill };
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 112));
        row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        row.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        control.Dock = DockStyle.Fill;
        control.AccessibleName = label;
        row.Controls.Add(control, 1, 0);
        return row;
    }
    private static Control SliderRow(string label, TrackBar slider, Label value)
    {
        var panel = new TableLayoutPanel { ColumnCount = 2, AutoSize = true, Dock = DockStyle.Fill };
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        panel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 60));
        panel.Controls.Add(slider, 0, 0);
        value.Anchor = AnchorStyles.Right;
        panel.Controls.Add(value, 1, 0);
        slider.AccessibleName = label;
        return Row(label, panel);
    }
    private static void Add(TableLayoutPanel layout, Control control, int bottom = 7)
    {
        control.Margin = new Padding(0, 0, 0, bottom);
        control.Dock = DockStyle.Fill;
        layout.Controls.Add(control);
    }
}
