namespace StarfieldSaver;

static class Program
{
    [STAThread]
    static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();

        // Windows passes: /s (run), /c[:hwnd] (configure), /p <hwnd> (preview). No args = configure.
        var mode = "/c";
        var preview = IntPtr.Zero;
        if (args.Length > 0)
        {
            var first = args[0].Trim().ToLowerInvariant();
            mode = first.Length >= 2 ? first[..2] : first;
            var rest = first.Length > 3 && first[2] == ':' ? first[3..] : (args.Length > 1 ? args[1] : null);
            if (mode == "/p" && long.TryParse(rest, out var h)) preview = new IntPtr(h);
        }

        var settings = Settings.Load();
        switch (mode)
        {
            case "/s":
                var screens = Screen.AllScreens;
                var forms = screens.Select(s => new SaverForm(s.Bounds, settings, watchInput: true)).ToArray();
                foreach (var f in forms.Skip(1)) f.Show();
                Application.Run(forms[0]);
                foreach (var f in forms.Skip(1)) f.Close();
                break;
            case "/p" when preview != IntPtr.Zero:
                Application.Run(new SaverForm(preview, settings));
                break;
            case "/p":
                break;
            default:
                Application.Run(new SettingsForm());
                break;
        }
    }
}
