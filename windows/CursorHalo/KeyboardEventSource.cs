using CursorHalo.Core;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace CursorHalo;

internal readonly record struct KeyboardShortcut(uint Key, KeyboardModifiers Modifiers, nint Layout);

/// A dedicated hook thread forwards only the latest shortcut. Ordinary typing
/// and AltGr events are discarded in the callback; no input history is retained.
internal sealed class KeyboardEventSource : IDisposable
{
    private readonly nint receiver;
    private readonly object gate = new();
    private readonly ManualResetEventSlim ready = new();
    private readonly Native.HookProc callback;
    private readonly Thread thread;
    private KeyboardShortcut? latest;
    private bool posted;
    private volatile bool disposed;
    private uint threadId;
    private nint hook;
    private Exception? startupError;
    internal bool IsRunning => thread.IsAlive;

    internal KeyboardEventSource(nint receiver)
    {
        this.receiver = receiver;
        callback = OnKeyboard;
        thread = new Thread(Run) { IsBackground = true, Name = "Cursor Halo keyboard shortcuts" };
        thread.Start();
        if (!ready.Wait(TimeSpan.FromSeconds(5)))
        {
            Dispose();
            throw new TimeoutException("Keyboard observation did not start. Try toggling the halo again.");
        }
        if (startupError != null) { Dispose(); throw startupError; }
    }

    internal KeyboardShortcut? Drain()
    {
        lock (gate)
        {
            var shortcut = latest;
            latest = null;
            posted = false;
            return shortcut;
        }
    }

    private void Run()
    {
        threadId = Native.GetCurrentThreadId();
        try
        {
            hook = Native.SetWindowsHookEx(Native.WhKeyboardLl, callback, Native.GetModuleHandle(null), 0);
            if (hook == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "Couldn’t observe keyboard shortcuts.");
            ready.Set();
            while (!disposed && Native.GetMessage(out var message, 0, 0, 0) > 0)
            {
                Native.TranslateMessage(ref message);
                Native.DispatchMessage(ref message);
            }
        }
        catch (Exception error) { startupError = error; ready.Set(); }
        finally
        {
            if (hook != 0) Native.UnhookWindowsHookEx(hook);
            hook = 0;
        }
    }

    private nint OnKeyboard(int code, nint wParam, nint lParam)
    {
        if (code >= 0 && !disposed && (wParam == 0x100 || wParam == 0x104))
        {
            var data = Marshal.PtrToStructure<Native.KeyboardData>(lParam);
            // The current key's asynchronous state is not updated yet. Read
            // only modifiers on a non-modifier keydown, whose state is current.
            if (KeyboardShortcutFormatter.IsCandidate(data.VirtualKey, KeyboardModifiers.Control))
            {
                var modifiers = KeyboardModifiers.None;
                if (Pressed(0x11)) modifiers |= KeyboardModifiers.Control;
                if (Pressed(0x12)) modifiers |= KeyboardModifiers.Alt;
                if (Pressed(0x10)) modifiers |= KeyboardModifiers.Shift;
                if (Pressed(0x5B) || Pressed(0x5C)) modifiers |= KeyboardModifiers.Windows;
                if (Pressed(0xA5)) modifiers |= KeyboardModifiers.AltGr;
                if (KeyboardShortcutFormatter.IsCandidate(data.VirtualKey, modifiers))
                {
                    var foregroundThread = Native.GetWindowThreadProcessId(Native.GetForegroundWindow(), out _);
                    var shortcut = new KeyboardShortcut(data.VirtualKey, modifiers, Native.GetKeyboardLayout(foregroundThread));
                    bool notify;
                    lock (gate)
                    {
                        latest = shortcut;
                        notify = !posted;
                        posted = true;
                    }
                    if (notify && !Native.PostMessage(receiver, Native.WmKeyboardUpdate, 0, 0))
                        lock (gate) posted = false;
                }
            }
        }
        return Native.CallNextHookEx(hook, code, wParam, lParam);
    }

    private static bool Pressed(int key) => (Native.GetAsyncKeyState(key) & 0x8000) != 0;

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (threadId != 0) Native.PostThreadMessage(threadId, Native.WmQuit, 0, 0);
        thread.Join(TimeSpan.FromSeconds(2));
        lock (gate) { latest = null; posted = false; }
        if (!thread.IsAlive) ready.Dispose();
    }
}
