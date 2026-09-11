using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.IO;

namespace AVDB.Win;

public sealed class JavdbClient
{
    const string Str1 = "71cf27bb3c0bcdf207b64abecddc970098c7421ee7203b9cdae54478478a199e7d5a6e1a57691123c1a931c057842fb73ba3b3c83bcd69c17ccf174081e3d8aa";
    const string Str2 = "lpw6vgqzsp";
    static readonly string[] Bases = ["https://jdforrepam.com", "https://apidd.spthgb.com"];
    static readonly Lazy<JavdbClient> LazyShared = new(() => new JavdbClient());

    public static JavdbClient Shared => LazyShared.Value;

    readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(28) };
    readonly object _gate = new();
    string _base = "https://jdforrepam.com";
    string? _token;

    public JavdbClient()
    {
        _token = LoadToken();
    }

    public string? Token
    {
        get { lock (_gate) return _token; }
        set
        {
            lock (_gate) _token = value;
            SaveToken(value);
        }
    }

    public bool LoggedIn => !string.IsNullOrEmpty(Token);

    static string DataDir()
    {
        var root = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        if (string.IsNullOrEmpty(root))
            root = Path.GetTempPath();
        var dir = Path.Combine(root, "AVDB");
        Directory.CreateDirectory(dir);
        return dir;
    }

    static string TokenPath() => Path.Combine(DataDir(), "token.txt");

    static string? LoadToken()
    {
        try
        {
            var p = TokenPath();
            return File.Exists(p) ? File.ReadAllText(p).Trim() : null;
        }
        catch { return null; }
    }

    static void SaveToken(string? token)
    {
        try
        {
            var p = TokenPath();
            if (string.IsNullOrEmpty(token)) File.Delete(p);
            else File.WriteAllText(p, token);
        }
        catch { }
    }

    static string Sign()
    {
        var ts = DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString();
        var md5 = Convert.ToHexString(MD5.HashData(Encoding.UTF8.GetBytes(ts + Str1))).ToLowerInvariant();
        return $"{ts}.{Str2}.{md5}";
    }

    public async Task<JsonElement> GetAsync(string path, Dictionary<string, string>? query = null, bool useToken = false, CancellationToken ct = default)
    {
        var q = new Dictionary<string, string>
        {
            ["platform"] = "ios",
            ["app_channel"] = "official",
            ["app_version"] = "official",
            ["app_version_number"] = "1.9.28",
            ["system_version"] = "18.0",
        };
        if (query != null)
            foreach (var kv in query) q[kv.Key] = kv.Value;
        var qs = string.Join("&", q.Select(kv => $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}"));
        Exception? last = null;
        var bases = new List<string> { _base };
        bases.AddRange(Bases.Where(b => b != _base));
        foreach (var host in bases)
        {
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Get, $"{host}{path}?{qs}");
                ApplyHeaders(req, useToken);
                using var resp = await _http.SendAsync(req, ct);
                var json = await resp.Content.ReadAsStringAsync(ct);
                if ((int)resp.StatusCode >= 500) { last = new Exception($"HTTP {(int)resp.StatusCode}"); continue; }
                _base = host;
                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(json) ? "{}" : json);
                return doc.RootElement.Clone();
            }
            catch (Exception ex) { last = ex; }
        }
        throw last ?? new Exception("请求失败");
    }

    public async Task<JsonElement> PostFormAsync(string path, Dictionary<string, string> form, bool useToken = false, CancellationToken ct = default)
    {
        var q = "platform=ios&app_channel=official&app_version=official&app_version_number=1.9.28&system_version=18.0";
        Exception? last = null;
        var bases = new List<string> { _base };
        bases.AddRange(Bases.Where(b => b != _base));
        foreach (var host in bases)
        {
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Post, $"{host}{path}?{q}");
                ApplyHeaders(req, useToken);
                req.Content = new FormUrlEncodedContent(form);
                using var resp = await _http.SendAsync(req, ct);
                var json = await resp.Content.ReadAsStringAsync(ct);
                if ((int)resp.StatusCode >= 500) { last = new Exception($"HTTP {(int)resp.StatusCode}"); continue; }
                _base = host;
                using var doc = JsonDocument.Parse(string.IsNullOrWhiteSpace(json) ? "{}" : json);
                return doc.RootElement.Clone();
            }
            catch (Exception ex) { last = ex; }
        }
        throw last ?? new Exception("请求失败");
    }

    void ApplyHeaders(HttpRequestMessage req, bool useToken)
    {
        req.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
        req.Headers.TryAddWithoutValidation("jdsignature", Sign());
        req.Headers.TryAddWithoutValidation("accept-language", "zh-CN");
        if (useToken && !string.IsNullOrEmpty(Token))
            req.Headers.TryAddWithoutValidation("authorization", "Bearer " + Token);
    }

    public static List<MovieItem> MoviesOf(JsonElement root)
    {
        var list = new List<MovieItem>();
        if (!root.TryGetProperty("data", out var data)) return list;
        if (!data.TryGetProperty("movies", out var movies) || movies.ValueKind != JsonValueKind.Array) return list;
        foreach (var m in movies.EnumerateArray())
            list.Add(MovieItem.From(m));
        return list;
    }
}

public sealed class MovieItem
{
    public string Id { get; set; } = "";
    public string Number { get; set; } = "";
    public string Title { get; set; } = "";
    public string Cover { get; set; } = "";
    public string Date { get; set; } = "";

    public static MovieItem From(JsonElement m) => new()
    {
        Id = Str(m, "id"),
        Number = Str(m, "number"),
        Title = First(m, "title", "origin_title"),
        Cover = First(m, "cover_url", "thumb_url"),
        Date = Str(m, "release_date"),
    };

    static string Str(JsonElement e, string k) =>
        e.TryGetProperty(k, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() ?? "" : "";

    static string First(JsonElement e, params string[] keys)
    {
        foreach (var k in keys)
        {
            var s = Str(e, k);
            if (!string.IsNullOrEmpty(s)) return s;
        }
        return "";
    }
}
