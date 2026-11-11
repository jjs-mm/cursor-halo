using System.Text.Json;
using System.Text.Json.Serialization;

namespace CursorHalo.Core;

public readonly record struct SettingsLoadResult(HaloSettings Settings, string? Error, bool IsFirstRun);

/// Writes a complete temporary file on the same volume before replacing the old
/// file. A failed write leaves the previous settings intact.
public sealed class SettingsStore(string path)
{
    private const long MaximumFileBytes = 64 * 1024;
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    public SettingsLoadResult Load()
    {
        if (!File.Exists(path)) return new(new HaloSettings(), null, true);
        try
        {
            if (new FileInfo(path).Length > MaximumFileBytes)
                throw new InvalidDataException("The saved settings file is too large.");
            var settings = JsonSerializer.Deserialize<HaloSettings>(File.ReadAllText(path), Options)
                ?? throw new InvalidDataException("The saved settings are empty.");
            return new(settings.Sanitize(), null, false);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or InvalidDataException)
        {
            return new(new HaloSettings(), $"Couldn’t read saved settings. Defaults are in use. {error.Message}", false);
        }
    }

    public string? Save(HaloSettings settings)
    {
        string? temporary = null;
        try
        {
            var fullPath = Path.GetFullPath(path);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            temporary = fullPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(stream, settings.Sanitize(), Options);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, fullPath, overwrite: true);
            return null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            return $"Couldn’t save settings. Your changes work for this session. {error.Message}";
        }
        finally
        {
            if (temporary != null)
            {
                try { File.Delete(temporary); }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            }
        }
    }
}
