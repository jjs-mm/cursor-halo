namespace CursorHalo.Core;

[Flags]
public enum KeyboardModifiers { None = 0, Control = 1, Alt = 2, Shift = 4, Windows = 8, AltGr = 16 }

/// Formats one shortcut, never a sequence of typed text. AltGr is text entry,
/// even though Windows may report its synthetic Ctrl+Alt combination.
public static class KeyboardShortcutFormatter
{
    public static bool IsCandidate(uint key, KeyboardModifiers modifiers) =>
        (modifiers & (KeyboardModifiers.Control | KeyboardModifiers.Alt | KeyboardModifiers.Windows)) != 0
        && !modifiers.HasFlag(KeyboardModifiers.AltGr)
        && key is not (0x10 or 0x11 or 0x12 or 0x5B or 0x5C or 0xA0 or 0xA1 or 0xA2 or 0xA3 or 0xA4 or 0xA5);

    public static string? Format(uint key, KeyboardModifiers modifiers, string? layoutKey = null)
    {
        if (!IsCandidate(key, modifiers)) return null;
        var name = key switch
        {
            >= 0x41 and <= 0x5A => ((char)key).ToString(),
            >= 0x30 and <= 0x39 => ((char)key).ToString(),
            >= 0x70 and <= 0x87 => $"F{key - 0x6F}",
            >= 0x60 and <= 0x69 => $"Num {key - 0x60}",
            0x08 => "Backspace", 0x09 => "Tab", 0x0D => "Enter", 0x13 => "Pause",
            0x14 => "Caps Lock", 0x1B => "Esc", 0x20 => "Space", 0x21 => "Page Up",
            0x22 => "Page Down", 0x23 => "End", 0x24 => "Home", 0x25 => "←",
            0x26 => "↑", 0x27 => "→", 0x28 => "↓", 0x2C => "Print Screen",
            0x2D => "Insert", 0x2E => "Delete", 0x5D => "Menu", 0x6A => "Num ×",
            0x6B => "Num +", 0x6D => "Num −", 0x6E => "Num .", 0x6F => "Num /",
            0x90 => "Num Lock", 0x91 => "Scroll Lock", _ => layoutKey
        };
        if (string.IsNullOrWhiteSpace(name) || name.Length > 16 || name.Any(char.IsControl)) return null;
        var parts = new List<string>(5);
        if (modifiers.HasFlag(KeyboardModifiers.Control)) parts.Add("Ctrl");
        if (modifiers.HasFlag(KeyboardModifiers.Alt)) parts.Add("Alt");
        if (modifiers.HasFlag(KeyboardModifiers.Shift)) parts.Add("Shift");
        if (modifiers.HasFlag(KeyboardModifiers.Windows)) parts.Add("Win");
        parts.Add(name);
        return string.Join(" + ", parts);
    }
}
