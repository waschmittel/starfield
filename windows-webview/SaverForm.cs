using System.Globalization;
using System.Reflection;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using static StarfieldSaver.NativeMethods;

namespace StarfieldSaver;

/// <summary>One borderless window per monitor (or a child window in the Settings preview pane).</summary>
sealed class SaverForm : Form
{
    const int PreviewStarCap = 300;
    const int GraceMs = 800;
    const int MouseThresholdPx = 6;

    static readonly Task<CoreWebView2Environment> WebEnv =
        CoreWebView2Environment.CreateAsync(null, Settings.WebViewDataDir);

    static readonly string Html = LoadHtml();

    readonly WebView2 web = new() { Dock = DockStyle.Fill, DefaultBackgroundColor = Color.Black };
    readonly System.Windows.Forms.Timer poll = new() { Interval = 50 };
    readonly Settings settings;
    readonly bool preview;
    readonly IntPtr previewParent;
    readonly bool watchInput;
    POINT startCursor;
    DateTime startedAt = DateTime.UtcNow;

    public SaverForm(Rectangle bounds, Settings settings, bool watchInput)
    {
        this.settings = settings;
        this.watchInput = watchInput;
        Setup();
        StartPosition = FormStartPosition.Manual;
        Bounds = bounds;
        TopMost = true;
    }

    public SaverForm(IntPtr previewParent, Settings settings)
    {
        this.settings = settings;
        this.previewParent = previewParent;
        preview = true;
        Setup();
    }

    void Setup()
    {
        FormBorderStyle = FormBorderStyle.None;
        BackColor = Color.Black;
        ShowInTaskbar = false;
        Controls.Add(web);
        poll.Tick += (_, _) => Poll();
    }

    static string LoadHtml()
    {
        using var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("starfield.html")!;
        using var r = new StreamReader(s);
        return r.ReadToEnd();
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        if (!preview) return;
        SetParent(Handle, previewParent);
        SetWindowLongPtr(Handle, GWL_STYLE, new IntPtr(WS_CHILD | WS_VISIBLE));
        GetClientRect(previewParent, out var r);
        Bounds = new Rectangle(0, 0, r.Right - r.Left, r.Bottom - r.Top);
    }

    protected override async void OnShown(EventArgs e)
    {
        base.OnShown(e);
        GetCursorPos(out startCursor);
        startedAt = DateTime.UtcNow;
        if (!preview) Cursor.Hide();
        poll.Start();

        await web.EnsureCoreWebView2Async(await WebEnv);
        var cw = web.CoreWebView2;
        cw.Settings.AreDefaultContextMenusEnabled = false;
        cw.Settings.AreDevToolsEnabled = false;
        cw.Settings.IsStatusBarEnabled = false;
        cw.Settings.IsZoomControlEnabled = false;
        cw.Settings.AreBrowserAcceleratorKeysEnabled = false;
        cw.NavigationCompleted += (_, _) => ApplyConfig();
        web.NavigateToString(Html);
    }

    void ApplyConfig()
    {
        var stars = preview ? Math.Min(settings.StarCount, PreviewStarCap) : settings.StarCount;
        var js = string.Create(CultureInfo.InvariantCulture,
            $"window.setConfig({{speed:{settings.Speed},trailLength:{settings.TrailLength},starCount:{stars}}})");
        _ = web.ExecuteScriptAsync(js);
    }

    // WebView2 owns its own input windows, so form events never see input; poll the OS instead.
    void Poll()
    {
        if (preview)
        {
            if (!IsWindow(previewParent)) Application.Exit();
            return;
        }
        if (!watchInput || (DateTime.UtcNow - startedAt).TotalMilliseconds < GraceMs) return;

        GetCursorPos(out var p);
        if (Math.Abs(p.X - startCursor.X) > MouseThresholdPx || Math.Abs(p.Y - startCursor.Y) > MouseThresholdPx)
        {
            Application.Exit();
            return;
        }
        for (var vk = 1; vk < 255; vk++)
        {
            if ((GetAsyncKeyState(vk) & 0x8000) != 0)
            {
                Application.Exit();
                return;
            }
        }
    }

    protected override void OnFormClosed(FormClosedEventArgs e)
    {
        poll.Stop();
        if (!preview) Cursor.Show();
        base.OnFormClosed(e);
    }
}
