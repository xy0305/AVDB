using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace AVDB.Win;

public partial class MainWindow : Window
{
    readonly JavdbClient _api = JavdbClient.Shared;
    string _page = "home";
    string _catalog = "all";
    string _filter = "";
    string _sort = "update";

    public MainWindow()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            RefreshUser();
            await LoadHome();
        };
    }

    void RefreshUser()
    {
        UserLabel.Text = _api.LoggedIn ? "已登录" : "未登录";
        LoginButton.Content = _api.LoggedIn ? "退出" : "登录";
    }

    async void OnNav(object sender, RoutedEventArgs e)
    {
        if (sender == NavHome) { _page = "home"; await LoadHome(); }
        else if (sender == NavLatest) { _page = "latest"; _filter = ""; await LoadLatest(); }
        else if (sender == NavMagnets) { _page = "magnets"; _filter = "magnets"; await LoadLatest(); }
        else if (sender == NavSearch) ShowMessage("输入关键词后点搜索");
    }

    async void OnSearchClick(object sender, RoutedEventArgs e) => await DoSearch();
    async void OnSearchKey(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) await DoSearch();
    }

    async Task DoSearch()
    {
        var q = SearchBox.Text.Trim();
        if (q.Length == 0) return;
        _page = "search";
        NavSearch.IsChecked = true;
        ShowMessage("搜索中…");
        try
        {
            var json = await _api.GetAsync("/api/v2/search", new()
            {
                ["q"] = q, ["type"] = "movie", ["page"] = "1", ["limit"] = "24", ["movie_sort_by"] = "relevance"
            });
            RenderGrid("搜索：" + q, JavdbClient.MoviesOf(json));
        }
        catch (Exception ex) { ShowMessage(ex.Message); }
    }

    async Task LoadHome()
    {
        ShowMessage("加载首页…");
        try
        {
            var rec = await _api.GetAsync("/api/v1/movies/recommend", new() { ["page"] = "1" });
            var latest = await _api.GetAsync("/api/v1/movies/latest", new()
            {
                ["page"] = "1", ["limit"] = "18", ["type"] = "all", ["filter_by"] = "can_play", ["sort_by"] = "update"
            });
            ContentRoot.Children.Clear();
            ContentRoot.Children.Add(Section("佳片推荐", JavdbClient.MoviesOf(rec)));
            ContentRoot.Children.Add(Section("最新上架", JavdbClient.MoviesOf(latest)));
        }
        catch (Exception ex) { ShowMessage(ex.Message); }
    }

    async Task LoadLatest()
    {
        ShowMessage("加载中…");
        try
        {
            var q = new Dictionary<string, string> { ["page"] = "1", ["limit"] = "24", ["type"] = _catalog, ["sort_by"] = _sort };
            if (!string.IsNullOrEmpty(_filter)) q["filter_by"] = _filter;
            var json = await _api.GetAsync("/api/v1/movies/latest", q);
            ContentRoot.Children.Clear();
            ContentRoot.Children.Add(FilterBar());
            ContentRoot.Children.Add(MovieGrid(JavdbClient.MoviesOf(json)));
        }
        catch (Exception ex) { ShowMessage(ex.Message); }
    }

    UIElement FilterBar()
    {
        var panel = new WrapPanel { Margin = new Thickness(0, 0, 0, 16) };
        void Chip(string title, bool on, Action act)
        {
            var b = new Button
            {
                Content = title,
                Margin = new Thickness(0, 0, 8, 8),
                Background = on ? (Brush)FindResource("Accent") : new SolidColorBrush(Color.FromRgb(240, 240, 240)),
                Foreground = on ? Brushes.White : (Brush)FindResource("Text")
            };
            b.Click += async (_, _) => { act(); await LoadLatest(); };
            panel.Children.Add(b);
        }
        foreach (var (v, n) in new (string, string)[] { ("all", "全部"), ("0", "有码"), ("1", "无码"), ("2", "欧美"), ("3", "FC2"), ("4", "动漫") })
            Chip(n, _catalog == v, () => _catalog = v);
        Chip("筛选全部", _filter == "", () => _filter = "");
        Chip("含磁链", _filter == "magnets", () => _filter = "magnets");
        Chip("可播放", _filter == "can_play", () => _filter = "can_play");
        Chip("字幕", _filter == "subtitle", () => _filter = "subtitle");
        Chip("更新时间倒序", _sort == "update", () => _sort = "update");
        Chip("发布日期倒序", _sort == "release", () => _sort = "release");
        return panel;
    }

    UIElement Section(string title, List<MovieItem> movies)
    {
        var box = new StackPanel { Margin = new Thickness(0, 0, 0, 24) };
        box.Children.Add(new TextBlock { Text = title, FontSize = 20, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 12) });
        box.Children.Add(MovieGrid(movies));
        return box;
    }

    UIElement MovieGrid(List<MovieItem> movies)
    {
        var wrap = new WrapPanel();
        if (movies.Count == 0)
            wrap.Children.Add(new TextBlock { Text = "没有内容", Foreground = (Brush)FindResource("Muted") });
        foreach (var m in movies) wrap.Children.Add(MovieCard(m));
        return wrap;
    }

    UIElement MovieCard(MovieItem m)
    {
        var img = new Image { Stretch = Stretch.UniformToFill, Height = 240, Width = 160 };
        _ = FillCover(img, m.Cover);
        var card = new Border
        {
            Width = 168, Margin = new Thickness(0, 0, 14, 16), Background = Brushes.White,
            CornerRadius = new CornerRadius(10), Cursor = Cursors.Hand,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 12, Opacity = 0.12, ShadowDepth = 2 }
        };
        var stack = new StackPanel();
        stack.Children.Add(new Border { CornerRadius = new CornerRadius(10, 10, 0, 0), ClipToBounds = true, Child = img });
        stack.Children.Add(new TextBlock { Text = m.Number, Foreground = (Brush)FindResource("Accent"), Margin = new Thickness(8, 8, 8, 0), FontWeight = FontWeights.SemiBold });
        stack.Children.Add(new TextBlock { Text = m.Title, TextWrapping = TextWrapping.Wrap, MaxHeight = 40, Margin = new Thickness(8, 2, 8, 0) });
        stack.Children.Add(new TextBlock { Text = m.Date, Foreground = (Brush)FindResource("Muted"), FontSize = 12, Margin = new Thickness(8, 4, 8, 10) });
        card.Child = stack;
        card.MouseLeftButtonUp += async (_, _) => await OpenMovie(m.Id);
        return card;
    }

    async Task FillCover(Image img, string url)
    {
        var bmp = await CoverLoader.LoadAsync(url);
        if (bmp != null) img.Source = bmp;
    }

    async Task OpenMovie(string id)
    {
        ShowMessage("加载详情…");
        try
        {
            var json = await _api.GetAsync("/api/v4/movies/" + Uri.EscapeDataString(id), useToken: _api.LoggedIn);
            JsonElement data = json.TryGetProperty("data", out var d) ? d : json;
            if (data.TryGetProperty("movie", out var nested)) data = nested;
            var title = GetStr(data, "number") + " " + GetStr(data, "title");
            var cover = GetStr(data, "cover_url");
            var summary = GetStr(data, "summary");
            JsonElement magnets = default;
            try
            {
                var mj = await _api.GetAsync("/api/v1/movies/" + Uri.EscapeDataString(id) + "/magnets", new() { ["page"] = "1" });
                if (mj.TryGetProperty("data", out var md) && md.TryGetProperty("magnets", out var arr)) magnets = arr;
            }
            catch { }

            ContentRoot.Children.Clear();
            var grid = new Grid();
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(280) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var coverImg = new Image { Stretch = Stretch.UniformToFill, Height = 400 };
            _ = FillCover(coverImg, cover);
            var left = new Border { CornerRadius = new CornerRadius(12), ClipToBounds = true, Child = coverImg, Margin = new Thickness(0, 0, 20, 0) };
            Grid.SetColumn(left, 0);
            var right = new StackPanel();
            right.Children.Add(new TextBlock { Text = title, FontSize = 22, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
            right.Children.Add(new TextBlock { Text = GetStr(data, "release_date"), Foreground = (Brush)FindResource("Muted"), Margin = new Thickness(0, 6, 0, 12) });
            if (data.TryGetProperty("tags", out var tags) && tags.ValueKind == JsonValueKind.Array)
            {
                var chips = new WrapPanel { Margin = new Thickness(0, 0, 0, 12) };
                foreach (var t in tags.EnumerateArray())
                    chips.Children.Add(new Border
                    {
                        Background = new SolidColorBrush(Color.FromRgb(240, 240, 240)),
                        CornerRadius = new CornerRadius(12),
                        Padding = new Thickness(10, 4, 10, 4),
                        Margin = new Thickness(0, 0, 8, 8),
                        Child = new TextBlock { Text = GetStr(t, "name") }
                    });
                right.Children.Add(chips);
            }
            right.Children.Add(new TextBlock { Text = summary, TextWrapping = TextWrapping.Wrap, Foreground = (Brush)FindResource("Muted"), Margin = new Thickness(0, 0, 0, 16) });
            right.Children.Add(new TextBlock { Text = "磁力", FontSize = 18, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8) });
            if (magnets.ValueKind == JsonValueKind.Array)
            {
                foreach (var mag in magnets.EnumerateArray())
                {
                    var link = GetStr(mag, "magnet");
                    if (string.IsNullOrEmpty(link)) link = GetStr(mag, "url");
                    var tb = new TextBox { Text = link, IsReadOnly = true, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 0, 0, 8) };
                    right.Children.Add(tb);
                }
            }
            Grid.SetColumn(right, 1);
            grid.Children.Add(left);
            grid.Children.Add(right);
            ContentRoot.Children.Add(grid);
        }
        catch (Exception ex) { ShowMessage(ex.Message); }
    }

    static string GetStr(JsonElement e, string k) =>
        e.ValueKind == JsonValueKind.Object && e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";

    async void OnLoginClick(object sender, RoutedEventArgs e)
    {
        if (_api.LoggedIn)
        {
            _api.Token = null;
            RefreshUser();
            return;
        }
        var user = Prompt("用户名");
        if (user == null) return;
        var pass = Prompt("密码", password: true);
        if (pass == null) return;
        try
        {
            var json = await _api.PostFormAsync("/api/v1/sessions", new()
            {
                ["username"] = user,
                ["password"] = pass,
                ["device_uuid"] = "win11-avdb",
                ["device_name"] = "AVDB-Win",
                ["device_model"] = "Windows",
                ["platform"] = "ios",
                ["system_version"] = "18.0",
                ["app_channel"] = "official",
                ["app_version"] = "official",
                ["app_version_number"] = "1.9.28",
            });
            var ok = json.TryGetProperty("success", out var s) && s.ValueKind == JsonValueKind.Number && s.GetDouble() == 1;
            if (!ok)
            {
                var msg = json.TryGetProperty("message", out var m) ? m.GetString() : "登录失败";
                MessageBox.Show(msg, "AVDB");
                return;
            }
            if (json.TryGetProperty("data", out var data) && data.TryGetProperty("token", out var t))
                _api.Token = t.GetString();
            RefreshUser();
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "AVDB"); }
    }

    static string? Prompt(string title, bool password = false)
    {
        var w = new Window
        {
            Title = title, Width = 360, Height = 160, WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize, Background = Brushes.White
        };
        var box = password ? new PasswordBox { Margin = new Thickness(16) } : null;
        var tb = password ? null : new TextBox { Margin = new Thickness(16) };
        var ok = new Button { Content = "确定", Width = 80, Margin = new Thickness(0, 0, 16, 16), HorizontalAlignment = HorizontalAlignment.Right };
        ok.Click += (_, _) => w.DialogResult = true;
        var dock = new DockPanel();
        DockPanel.SetDock(ok, Dock.Bottom);
        dock.Children.Add(ok);
        dock.Children.Add(password ? box! : tb!);
        w.Content = dock;
        w.Owner = Application.Current.MainWindow;
        return w.ShowDialog() == true ? (password ? box!.Password : tb!.Text) : null;
    }

    void ShowMessage(string text)
    {
        ContentRoot.Children.Clear();
        ContentRoot.Children.Add(new TextBlock { Text = text, Foreground = (Brush)FindResource("Muted"), Margin = new Thickness(0, 40, 0, 0) });
    }
}
