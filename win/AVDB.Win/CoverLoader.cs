using System.IO;
using System.Net.Http;
using System.Windows.Media.Imaging;

namespace AVDB.Win;

public static class CoverLoader
{
    static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(20) };

    public static async Task<BitmapImage?> LoadAsync(string url, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, url);
            req.Headers.TryAddWithoutValidation("User-Agent", "Mozilla/5.0");
            req.Headers.TryAddWithoutValidation("Referer", "https://javdb.com/");
            using var resp = await Http.SendAsync(req, ct);
            var bytes = await resp.Content.ReadAsByteArrayAsync(ct);
            if (LooksEncrypted(bytes)) bytes = Decrypt(bytes);
            if (bytes.Length < 8) return null;
            var img = new BitmapImage();
            using var ms = new MemoryStream(bytes);
            img.BeginInit();
            img.CacheOption = BitmapCacheOption.OnLoad;
            img.StreamSource = ms;
            img.EndInit();
            img.Freeze();
            return img;
        }
        catch { return null; }
    }

    static bool LooksEncrypted(byte[] b)
    {
        if (b.Length < 12) return false;
        if (b[0] == 0xFF && b[1] == 0xD8) return false;
        if (b.Length >= 8 && b[0] == 0x89 && b[1] == 0x50) return false;
        if (b.Length >= 6 && b[0] == 'G' && b[1] == 'I' && b[2] == 'F') return false;
        return true;
    }

    static byte[] Decrypt(byte[] enc)
    {
        if (enc.Length < 2) return enc;
        var key = enc[0];
        var outb = new byte[enc.Length - 1];
        for (var i = 1; i < enc.Length; i++) outb[i - 1] = (byte)(enc[i] ^ key);
        return outb;
    }
}
