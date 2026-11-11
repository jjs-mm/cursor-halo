using CursorHalo.Core;
using System.Collections.Concurrent;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace CursorHalo;

internal sealed class MessageWindow : NativeWindow, IDisposable
{
    internal const string WindowTitle = "Cursor Halo message receiver";
    internal static readonly uint RevealMessage = Native.RegisterWindowMessage("CursorHalo.ShowSettings.1");
    private readonly ConcurrentQueue<Action> actions = new();
    private ToggleShortcut? registeredShortcut;
    private int activeHotKeyId;
    private bool disposed;
    internal ToggleShortcut? RegisteredShortcut => registeredShortcut;
    internal int ActiveHotKeyId => activeHotKeyId;
    internal event Action? ToggleRequested;
    internal event Action? SettingsRequested;
    internal event Action? PointerUpdated;
    internal event Action? KeyboardUpdated;

    internal MessageWindow()
    {
        CreateHandle(new CreateParams { Caption = WindowTitle, ExStyle = Native.WsExToolWindow, Width = 1, Height = 1 });
    }

    internal string? RegisterShortcut(ToggleShortcut shortcut)
    {
        if (registeredShortcut == shortcut) return null;
        // Reserve a different ID first, preserving the working registration if
        // Windows rejects the replacement because another application owns it.
        var candidateId = activeHotKeyId == 1 ? 2 : 1;
        var key = shortcut == ToggleShortcut.ControlAltC ? (uint)Keys.C : (uint)Keys.H;
        var modifiers = 0x4000u | 0x2u | (shortcut == ToggleShortcut.ControlShiftH ? 0x4u : 0x1u);
        if (!Native.RegisterHotKey(Handle, candidateId, modifiers, key))
            return $"The shortcut is unavailable. Choose another combination. ({new Win32Exception(Marshal.GetLastWin32Error()).Message})";
        if (activeHotKeyId != 0) Native.UnregisterHotKey(Handle, activeHotKeyId);
        activeHotKeyId = candidateId;
        registeredShortcut = shortcut;
        return null;
    }

    internal void Post(Action action)
    {
        if (disposed) return;
        actions.Enqueue(action);
        Native.PostMessage(Handle, Native.WmAction, 0, 0);
    }

    protected override void WndProc(ref System.Windows.Forms.Message message)
    {
        if (message.Msg == RevealMessage) { SettingsRequested?.Invoke(); return; }
        switch (message.Msg)
        {
            case Native.WmHotKey when activeHotKeyId != 0 && message.WParam == activeHotKeyId: ToggleRequested?.Invoke(); return;
            case Native.WmPointerUpdate: PointerUpdated?.Invoke(); return;
            case Native.WmKeyboardUpdate: KeyboardUpdated?.Invoke(); return;
            case Native.WmAction:
                while (actions.TryDequeue(out var action)) action();
                return;
        }
        base.WndProc(ref message);
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (activeHotKeyId != 0) Native.UnregisterHotKey(Handle, activeHotKeyId);
        activeHotKeyId = 0;
        registeredShortcut = null;
        while (actions.TryDequeue(out _)) { }
        DestroyHandle();
    }
}
