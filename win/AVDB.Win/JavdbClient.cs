using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

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
            if (string.IsNullOrEmpty(token))
            {
                if (File.Exists(p)) File.Delete(p);
            }
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

    public Task<JsonElement> GetAsync(string path, Dictionary<string, string>? query = null, bool useToken = false, CancellationToken ct = default)
        => SendAsync(HttpMethod.Get, path, query, null, useToken, ct);

    public Task<JsonElement> PostFormAsync(string path, Dictionary<string, string> form, bool useToken = false, CancellationToken ct = default)
        => SendAsync(HttpMethod.Post, path, null, form, useToken, ct);

    async Task<JsonElement> SendAsync(
        HttpMethod method, string path, Dictionary<string, string>? query,
        Dictionary<string, string>? form, bool useToken, CancellationToken ct)
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
            foreach (var kv in query)
                if (kv.Value != null) q[kv.Key] = kv.Value;
        var qs = string.Join("&", q.Select(kv => $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value)}"));

        Exception? last = null;
        var bases = new List<string> { _base };
        foreach (var b in Bases)
            if (!string.Equals(b, _base, StringComparison.Ordinal)) bases.Add(b);

        foreach (var host in bases)
        {
            try
            {
                using var req = new HttpRequestMessage(method, $"{host}{path}?{qs}");
                ApplyHeaders(req, useToken);
                if (form != null) req.Content = new FormUrlEncodedContent(form);
                using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
                var json = await resp.Content.ReadAsStringAsync(ct).ConfigureAwait(false);
                var code = (int)resp.StatusCode;
                if (code >= 500)
                {
                    last = new Exception($"HTTP {code}");
                    continue;
                }
                if (string.IsNullOrWhiteSpace(json) || json[0] is not ('{' or '['))
                {
                    last = new Exception(code >= 400 ? $"HTTP {code}" : "响应不是 JSON");
                    if (code >= 400) continue;
                    throw last;
                }
                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement.Clone();
                _base = host;
                if (root.ValueKind == JsonValueKind.Object &&
                    root.TryGetProperty("success", out var suc) &&
                    suc.ValueKind == JsonValueKind.Number &&
                    suc.GetDouble() == 0)
                {
                    var msg = "请求失败";
                    if (root.TryGetProperty("message", out var m) && m.ValueKind == JsonValueKind.String)
                        msg = m.GetString() ?? msg;
                    throw new Exception(msg);
                }
                return root;
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                last = ex;
            }
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
        JsonElement movies = default;
        if (root.ValueKind == JsonValueKind.Object && root.TryGetProperty("data", out var data))
        {
            if (data.ValueKind == JsonValueKind.Object && data.TryGetProperty("movies", out var m))
                movies = m;
            else if (data.ValueKind == JsonValueKind.Array)
                movies = data;
        }
        if (movies.ValueKind != JsonValueKind.Array) return list;
        foreach (var m in movies.EnumerateArray())
            if (m.ValueKind == JsonValueKind.Object)
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
        Id = Any(m, "id"),
        Number = Any(m, "number"),
        Title = First(m, "title", "origin_title"),
        Cover = First(m, "cover_url", "thumb_url"),
        Date = Any(m, "release_date"),
    };

    static string Any(JsonElement e, string k)
    {
        if (e.ValueKind != JsonValueKind.Object || !e.TryGetProperty(k, out var v)) return "";
        return v.ValueKind switch
        {
            JsonValueKind.String => v.GetString() ?? "",
            JsonValueKind.Number => v.ToString(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            _ => ""
        };
    }

    static string First(JsonElement e, params string[] keys)
    {
        foreach (var k in keys)
        {
            var s = Any(e, k);
            if (!string.IsNullOrEmpty(s)) return s;
        }
        return "";
    }
}
