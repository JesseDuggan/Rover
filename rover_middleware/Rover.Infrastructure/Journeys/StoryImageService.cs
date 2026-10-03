using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace Rover.Infrastructure.Journeys;

public sealed record StoryImageRequest(IReadOnlyList<string>? SourceUrls);
public sealed record StoryImage(string Url, string Caption, string Attribution, string License,
    string LicenseUrl, string SourceUrl, string ArticleUrl);
public sealed record StoryImageResult(string Status, IReadOnlyList<StoryImage> Images);

// Only resolve images attached to cited articles/entities, never a guessed image URL.
public sealed class StoryImageService(IHttpClientFactory clients, ILogger<StoryImageService> logger) : IDisposable
{
    private readonly MemoryCache cache = new(new MemoryCacheOptions { SizeLimit = 256 });

    public async Task<StoryImageResult> FindAsync(StoryImageRequest request, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (request.SourceUrls is null || request.SourceUrls.Count > 6
            || request.SourceUrls.Any(x => string.IsNullOrWhiteSpace(x) || x.Length > 2048))
            throw new ArgumentException("Provide up to six story source URLs.");
        var images = new List<StoryImage>();
        var failed = false;
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(TimeSpan.FromSeconds(12));
        foreach (var source in request.SourceUrls.Distinct())
        {
            if (!TryArticle(source, out var host, out var title)) continue;
            var key = host + "/" + title;
            if (cache.TryGetValue(key, out StoryImageResult? cached))
            {
                images.AddRange(cached!.Images);
                continue;
            }
            try
            {
                var image = await ResolveAsync(host, title, source, budget.Token);
                var result = new StoryImageResult(image is null ? "empty" : "ready", image is null ? [] : [image]);
                cache.Set(key, result, new MemoryCacheEntryOptions { Size = 1,
                    AbsoluteExpirationRelativeToNow = image is null ? TimeSpan.FromMinutes(10) : TimeSpan.FromHours(6) });
                images.AddRange(result.Images);
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
            catch (Exception ex) when (ex is HttpRequestException or JsonException or OperationCanceledException or InvalidOperationException or RegexMatchTimeoutException)
            {
                failed = true;
                logger.LogWarning("Story image lookup unavailable: {Kind}", ex.GetType().Name);
            }
            if (images.Count >= 3 || budget.IsCancellationRequested) break;
        }
        token.ThrowIfCancellationRequested();
        var unique = images.DistinctBy(x => x.SourceUrl).Take(3).ToArray();
        return new(unique.Length > 0 ? "ready" : failed ? "unavailable" : "empty", unique);
    }

    private async Task<StoryImage?> ResolveAsync(string host, string title, string article, CancellationToken token)
    {
        string? file = null;
        if (host == "www.wikidata.org")
        {
            using var entity = await ReadAsync($"https://www.wikidata.org/w/api.php?action=wbgetentities&ids={title}&props=claims&format=json", token);
            if (entity.RootElement.TryGetProperty("entities", out var entities)
                && entities.TryGetProperty(title, out var item) && item.TryGetProperty("claims", out var claims)
                && claims.TryGetProperty("P18", out var photos))
                foreach (var photo in photos.EnumerateArray())
                    if (photo.TryGetProperty("mainsnak", out var snak) && snak.TryGetProperty("datavalue", out var value))
                    { file = Text(value, "value"); break; }
        }
        else
        {
            using var page = await ReadAsync($"https://{host}/w/api.php?action=query&titles={Uri.EscapeDataString(title)}&redirects=1&prop=pageimages&piprop=name&pilicense=free&format=json&formatversion=2", token);
            foreach (var item in Pages(page)) { file = Text(item, "pageimage"); if (file is not null) break; }
        }
        if (string.IsNullOrWhiteSpace(file)) return null;
        using var details = await ReadAsync("https://commons.wikimedia.org/w/api.php?action=query&titles="
            + Uri.EscapeDataString("File:" + file)
            + "&prop=imageinfo&iiprop=url%7Cextmetadata%7Cmime&iiurlwidth=1000&format=json&formatversion=2", token);
        foreach (var page in Pages(details))
        {
            if (!page.TryGetProperty("imageinfo", out var infos)) continue;
            foreach (var info in infos.EnumerateArray())
            {
                if (Text(info, "mime") is not ("image/jpeg" or "image/png" or "image/webp")
                    || !info.TryGetProperty("extmetadata", out var meta)) continue;
                var license = Meta(meta, "LicenseShortName");
                var licenseUrl = Meta(meta, "LicenseUrl");
                if (licenseUrl.StartsWith("//")) licenseUrl = "https:" + licenseUrl;
                if (!Uri.TryCreate(licenseUrl, UriKind.Absolute, out var licenseUri)
                    || licenseUri.Scheme != "https" || licenseUri.Host != "creativecommons.org"
                    || !Regex.IsMatch(licenseUri.AbsolutePath, @"^/(licenses/(by|by-sa)/(1\.0|2\.0|2\.5|3\.0|4\.0)|publicdomain/(zero|mark)/1\.0)/$")) continue;
                var artist = Meta(meta, "Artist");
                var url = Text(info, "thumburl");
                var source = Text(info, "descriptionurl");
                if (string.IsNullOrWhiteSpace(artist) || string.IsNullOrWhiteSpace(license)
                    || !SafeUrl(url, "upload.wikimedia.org") || !SafeUrl(source, "commons.wikimedia.org")) continue;
                var credit = Meta(meta, "Credit");
                var attribution = Meta(meta, "Attribution");
                var caption = Meta(meta, "ImageDescription");
                return new(url!, string.IsNullOrWhiteSpace(caption) ? file : caption,
                    string.Join(" · ", new[] { artist, credit, attribution }.Where(x => !string.IsNullOrWhiteSpace(x)).Distinct()),
                    license, licenseUrl, source!, article);
            }
        }
        return null;
    }

    private async Task<JsonDocument> ReadAsync(string url, CancellationToken token)
    {
        using var client = clients.CreateClient("StoryImages");
        using var response = await client.GetAsync(url, token);
        response.EnsureSuccessStatusCode();
        return JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
    }
    private static IEnumerable<JsonElement> Pages(JsonDocument doc) =>
        doc.RootElement.TryGetProperty("query", out var q) && q.TryGetProperty("pages", out var p)
            ? p.EnumerateArray() : [];
    private static string? Text(JsonElement e, string key) =>
        e.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    private static string Meta(JsonElement meta, string key) => meta.TryGetProperty(key, out var item)
        ? WebUtility.HtmlDecode(Regex.Replace(Text(item, "value") ?? "", "<[^>]*>", "", RegexOptions.None, TimeSpan.FromMilliseconds(100))).Trim() : "";
    private static bool SafeUrl(string? url, string host) => Uri.TryCreate(url, UriKind.Absolute, out var uri)
        && uri.Scheme == "https" && uri.Host == host && uri.IsDefaultPort && uri.UserInfo.Length == 0;
    private static bool TryArticle(string source, out string host, out string title)
    {
        host = title = "";
        if (!Uri.TryCreate(source, UriKind.Absolute, out var uri) || uri.Scheme != "https"
            || !uri.IsDefaultPort || uri.UserInfo.Length != 0 || !uri.AbsolutePath.StartsWith("/wiki/")) return false;
        host = uri.Host;
        title = Uri.UnescapeDataString(uri.AbsolutePath[6..]);
        return host == "www.wikidata.org" ? Regex.IsMatch(title, "^Q[1-9][0-9]*$")
            : Regex.IsMatch(host, "^[a-z]{2,3}\\.wikipedia\\.org$") && title.Length > 0 && !title.Contains(':');
    }
    public void Dispose() => cache.Dispose();
}
