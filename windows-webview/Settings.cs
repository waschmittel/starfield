using System.Text.Json;

namespace StarfieldSaver;

sealed class Settings
{
    public double Speed { get; set; } = 6;
    public double TrailLength { get; set; } = 0.4;
    public int StarCount { get; set; } = 1200;

    static readonly string Dir =
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Starfield");
    static readonly string FilePath = Path.Combine(Dir, "settings.json");

    public static string WebViewDataDir => Path.Combine(Dir, "WebView2");

    public static Settings Load()
    {
        try
        {
            return JsonSerializer.Deserialize<Settings>(File.ReadAllText(FilePath)) ?? new Settings();
        }
        catch
        {
            return new Settings();
        }
    }

    public void Save()
    {
        Directory.CreateDirectory(Dir);
        File.WriteAllText(FilePath, JsonSerializer.Serialize(this));
    }
}
