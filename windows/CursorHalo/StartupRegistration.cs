using Microsoft.Win32;
using System.Security;

namespace CursorHalo;

internal readonly record struct StartupState(bool IsRegistered, bool Conflict, string? Error);

internal sealed class StartupRegistration
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "CursorHalo";
    private readonly string command;

    internal StartupRegistration()
    {
        var executable = Environment.ProcessPath;
        command = executable != null && string.Equals(Path.GetFileName(executable), "CursorHalo.exe", StringComparison.OrdinalIgnoreCase)
            ? $"\"{executable}\" --at-login" : "";
    }

    internal StartupState Read()
    {
        if (command.Length == 0) return new(false, false, "Use the packaged CursorHalo.exe to configure launch at login.");
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            var value = key?.GetValue(ValueName);
            var registered = value is string text && string.Equals(text, command, StringComparison.OrdinalIgnoreCase);
            var conflict = value != null && !registered;
            return new(registered, conflict, conflict ? "A different command uses Cursor Halo’s startup entry. Turn off launch at login in the previous copy, or remove its old startup entry, before enabling this copy." : null);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException)
        {
            return new(false, false, $"Couldn’t read the login setting. {error.Message}");
        }
    }

    internal string? SetEnabled(bool enabled)
    {
        var state = Read();
        if (state.Error != null) return state.Error;
        if (state.IsRegistered == enabled) return null;
        try
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey, writable: true);
            var existing = key.GetValue(ValueName);
            // Do not replace/remove a different command if another process changed
            // the value after Read. This utility owns only its exact command.
            if (existing != null && (existing is not string text || !string.Equals(text, command, StringComparison.OrdinalIgnoreCase)))
                return "The login entry changed. Review it in Windows Startup Apps and try again.";
            if (enabled) key.SetValue(ValueName, command, RegistryValueKind.String);
            else if (existing != null) key.DeleteValue(ValueName, throwOnMissingValue: false);
            return null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or SecurityException)
        {
            return $"Couldn’t change launch at login. {error.Message}";
        }
    }
}
