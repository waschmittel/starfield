namespace StarfieldSaver;

sealed class SettingsForm : Form
{
    readonly TrackBar speed = new() { Minimum = 5, Maximum = 300, TickFrequency = 25, Width = 220 };
    readonly TrackBar trail = new() { Minimum = 0, Maximum = 40, TickFrequency = 5, Width = 220 };
    readonly TrackBar stars = new() { Minimum = 50, Maximum = 5000, TickFrequency = 500, SmallChange = 50, LargeChange = 250, Width = 220 };
    readonly Label speedLabel = new() { Width = 50 };
    readonly Label trailLabel = new() { Width = 50 };
    readonly Label starsLabel = new() { Width = 50 };

    public SettingsForm()
    {
        Text = "Starfield Settings";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        AutoSize = true;
        AutoSizeMode = AutoSizeMode.GrowAndShrink;
        Padding = new Padding(12);

        var s = Settings.Load();
        speed.Value = Math.Clamp((int)Math.Round(s.Speed * 10), speed.Minimum, speed.Maximum);
        trail.Value = Math.Clamp((int)Math.Round(s.TrailLength * 10), trail.Minimum, trail.Maximum);
        stars.Value = Math.Clamp(s.StarCount, stars.Minimum, stars.Maximum);

        var grid = new TableLayoutPanel { AutoSize = true, ColumnCount = 3 };
        AddRow(grid, "Speed", speed, speedLabel);
        AddRow(grid, "Trail length", trail, trailLabel);
        AddRow(grid, "Star density", stars, starsLabel);

        var ok = new Button { Text = "OK", DialogResult = DialogResult.OK };
        var cancel = new Button { Text = "Cancel", DialogResult = DialogResult.Cancel };
        var buttons = new FlowLayoutPanel { FlowDirection = FlowDirection.RightToLeft, AutoSize = true, Dock = DockStyle.Fill };
        buttons.Controls.AddRange(new Control[] { cancel, ok });
        grid.Controls.Add(buttons, 0, 3);
        grid.SetColumnSpan(buttons, 3);
        Controls.Add(grid);

        AcceptButton = ok;
        CancelButton = cancel;
        ok.Click += (_, _) => Save();
        speed.ValueChanged += (_, _) => UpdateLabels();
        trail.ValueChanged += (_, _) => UpdateLabels();
        stars.ValueChanged += (_, _) => UpdateLabels();
        UpdateLabels();
    }

    static void AddRow(TableLayoutPanel grid, string caption, TrackBar bar, Label value)
    {
        grid.Controls.Add(new Label { Text = caption, AutoSize = true, Anchor = AnchorStyles.Right, Margin = new Padding(0, 10, 6, 0) });
        grid.Controls.Add(bar);
        value.Margin = new Padding(0, 10, 0, 0);
        grid.Controls.Add(value);
    }

    void UpdateLabels()
    {
        speedLabel.Text = (speed.Value / 10.0).ToString("0.0");
        trailLabel.Text = (trail.Value / 10.0).ToString("0.0");
        starsLabel.Text = stars.Value.ToString();
    }

    void Save() => new Settings
    {
        Speed = speed.Value / 10.0,
        TrailLength = trail.Value / 10.0,
        StarCount = stars.Value,
    }.Save();
}
