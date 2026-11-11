using CursorHalo.Core;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace CursorHalo;

internal readonly record struct ClickEvent(PixelPoint Point, bool Secondary);
internal readonly record struct PointerBatch(PixelPoint? Position, ClickEvent[] Clicks);

/// The hook runs on a dedicated message-loop thread. It only copies coordinates,
/// bounds a small queue, and posts a single coalesced UI message; it never draws,
/// waits for the UI thread, or writes preferences.
internal sealed class MouseEventSource : IDisposable
{
    private readonly nint receiver;
    private readonly object gate = new();
    private readonly Queue<ClickEvent> clicks = new();
    private readonly ManualResetEventSlim ready = new();
    private readonly Native.HookProc callback;
    private readonly Thread thread;
    private PixelPoint? latest;
    private bool posted;
    private volatile bool disposed;
    private uint threadId;
    private nint hook;
    private Exception? startupError;
    internal bool IsRunning => thread.IsAlive;

    internal MouseEventSource(nint receiver)
    {
        this.receiver = receiver;
        callback = OnMouse;
        thread = new Thread(Run) { IsBackground = true, Name = "Cursor Halo mouse events" };
        thread.Start();
        if (!ready.Wait(TimeSpan.FromSeconds(5)))
        {
            Dispose();
            throw new TimeoutException("Mouse observation did not start. Try toggling the halo again.");
        }
        if (startupError != null) { Dispose(); throw startupError; }
    }

    internal PointerBatch Drain()
    {
        lock (gate)
        {
            var batch = new PointerBatch(latest, clicks.ToArray());
            latest = null;
            clicks.Clear();
            posted = false;
            return batch;
        }
    }

    private void Run()
    {
        threadId = Native.GetCurrentThreadId();
        try
        {
            hook = Native.SetWindowsHookEx(Native.WhMouseLl, callback, Native.GetModuleHandle(null), 0);
            if (hook == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "Couldn’t observe mouse movement.");
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

    private nint OnMouse(int code, nint wParam, nint lParam)
    {
        if (code >= 0 && !disposed && (wParam == 0x200 || wParam == 0x201 || wParam == 0x204 || wParam == 0x207 || wParam == 0x20B))
        {
            var data = Marshal.PtrToStructure<Native.MouseData>(lParam);
            var position = new PixelPoint(data.Point.X, data.Point.Y);
            bool notify;
            lock (gate)
            {
                latest = position;
                if (wParam != 0x200)
                {
                    if (clicks.Count == 32) clicks.Dequeue();
                    clicks.Enqueue(new ClickEvent(position, wParam != 0x201));
                }
                notify = !posted;
                posted = true;
            }
            if (notify && !Native.PostMessage(receiver, Native.WmPointerUpdate, 0, 0))
            {
                // A full destination queue must not permanently suppress all
                // future updates. The next input event will retry delivery.
                lock (gate) posted = false;
            }
        }
        return Native.CallNextHookEx(hook, code, wParam, lParam);
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        if (threadId != 0) Native.PostThreadMessage(threadId, Native.WmQuit, 0, 0);
        // The callback cannot wait on the UI, so this is a bounded teardown.
        thread.Join(TimeSpan.FromSeconds(2));
        // Keep ready alive if startup is still finishing after an unusual timeout.
        if (!thread.IsAlive) ready.Dispose();
    }
}
