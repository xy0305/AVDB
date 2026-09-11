using System.IO;
using System.Net.Http;
using System.Windows.Media.Imaging;

namespace AVDB.Win;

public static class CoverLoader
{
    static readonly HttpClient Http = Create();

    static HttpClient Create()
    {
        var c = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
        c.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "Mozilla/5.0");
        c.DefaultRequestHeaders.TryAddWithoutValidation("Referer", "https://javdb.com/");
        return c;
    }

    public static async Task<BitmapImage?> LoadAsync(string url, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(url)) return null;
        if (!(url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
              url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)))
            return null;
        try
        {
            using var resp = await Http.GetAsync(url, ct).ConfigureAwait(false);
            if (!resp.IsSuccessStatusCode) return null;
            var bytes = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
            if (bytes.Length is < 8 or > 8_000_000) return null;
            if (LooksEncrypted(bytes)) bytes = Decrypt(bytes);
            if (bytes.Length < 8) return null;

            var img = new BitmapImage();
            using var ms = new MemoryStream(bytes, writable: false);
            img.BeginInit();
            img.CacheOption = BitmapCacheOption.OnLoad;
            img.CreateOptions = BitmapCreateOptions.IgnoreColorProfile;
            img.StreamSource = ms;
            img.EndInit();
            img.Freeze();
            return img;
        }
        catch
        {
            return null;
        }
    }

    static bool LooksEncrypted(byte[] b)
    {
        if (b.Length < 12) return false;
        if (b[0] == 0xFF && b[1] == 0xD8) return false;
        if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return false;
        if (b[0] == 'G' && b[1] == 'I' && b[2] == 'F') return false;
        if (b.Length >= 12 && b[8] == 'W' && b[9] == 'E' && b[10] == 'B' && b[11] == 'P') return false;
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
