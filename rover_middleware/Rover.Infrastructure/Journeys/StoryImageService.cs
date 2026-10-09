using System.Net;
using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;

namespace Rover.Infrastructure.Journeys;

public sealed record StoryImageRequest(IReadOnlyList<string>? SourceUrls, double? Latitude = null, double? Longitude = null);
public sealed record StoryImage(string Url, string Caption, string Attribution, string License,
    string LicenseUrl, string SourceUrl, string ArticleUrl, bool IsNearby = false,
    string Provider = "Wikimedia Commons", bool IsArchive = false);
public sealed record StoryImageResult(string Status, IReadOnlyList<StoryImage> Images);

// Resolve cited illustrations first; optional geotagged context is labelled as nearby, not as the POI itself.
public sealed class StoryImageService(IHttpClientFactory clients, ILogger<StoryImageService> logger,
    EuropeanaArchiveClient? europeana = null) : IDisposable
{
    private readonly MemoryCache cache = new(new MemoryCacheOptions { SizeLimit = 256 });

    public async Task<StoryImageResult> FindAsync(StoryImageRequest request, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (request.SourceUrls is null || request.SourceUrls.Count > 6
            || request.SourceUrls.Any(x => string.IsNullOrWhiteSpace(x) || x.Length > 2048))
            throw new ArgumentException("Provide up to six story source URLs.");
        if (request.Latitude.HasValue != request.Longitude.HasValue
            || request.Latitude is { } lat && (!double.IsFinite(lat) || lat < -90 || lat > 90)
            || request.Longitude is { } lng && (!double.IsFinite(lng) || lng < -180 || lng > 180))
            throw new ArgumentException("Provide valid latitude and longitude together.");
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
                if (images.Count >= 6) break;
                continue;
            }
            try
            {
                var found = await ResolveAsync(host, title, source, budget.Token);
                var result = new StoryImageResult(found.Count == 0 ? "empty" : "ready", found);
                cache.Set(key, result, new MemoryCacheEntryOptions { Size = 1,
                    AbsoluteExpirationRelativeToNow = found.Count == 0 ? TimeSpan.FromMinutes(10) : TimeSpan.FromHours(6) });
                images.AddRange(result.Images);
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
            catch (Exception ex) when (ex is HttpRequestException or JsonException or OperationCanceledException or InvalidOperationException or RegexMatchTimeoutException)
            {
                failed = true;
                logger.LogWarning("Story image lookup unavailable: {Kind}", ex.GetType().Name);
            }
            if (images.Count >= 6 || budget.IsCancellationRequested) break;
        }
        if (images.Count == 0 && request.Latitude.HasValue && !budget.IsCancellationRequested)
        {
            try { images.AddRange(await NearbyAsync(request.Latitude.Value, request.Longitude!.Value, budget.Token)); }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
            catch (Exception ex) when (ex is HttpRequestException or JsonException or OperationCanceledException or InvalidOperationException or RegexMatchTimeoutException)
            {
                failed = true;
                logger.LogWarning("Nearby image lookup unavailable: {Kind}", ex.GetType().Name);
            }
        }
        if (europeana is { Enabled: true } && images.Count < 6 && !budget.IsCancellationRequested)
        {
            var sources = request.SourceUrls.Concat(images.Select(i => i.ArticleUrl)).Distinct().Where(source =>
                EuropeanaArchiveClient.TryRecordId(source, out _) ||
                TryArticle(source, out var host, out _) && host.EndsWith(".wikipedia.org", StringComparison.Ordinal)).Take(2).ToArray();
            foreach (var source in sources)
            {
                try
                {
                    var archive = await europeana.FindPicturesAsync(source, budget.Token);
                    failed |= archive.Failed;
                    var nearby = images.Any(i => i.ArticleUrl == source && i.IsNearby);
                    images.AddRange(archive.Images.Select(i => i with { IsNearby = nearby }));
                }
                catch (OperationCanceledException) when (!token.IsCancellationRequested) { break; }
                if (images.Count >= 6 || budget.IsCancellationRequested) break;
            }
        }
        token.ThrowIfCancellationRequested();
        var unique = images.DistinctBy(x => x.SourceUrl).Take(6).ToArray();
        return new(unique.Length > 0 ? "ready" : failed ? "unavailable" : "empty", unique);
    }

    private async Task<IReadOnlyList<StoryImage>> ResolveAsync(string host, string title, string article, CancellationToken token)
    {
        var files = new List<string>();
        if (host == "www.wikidata.org")
        {
            using var entity = await ReadAsync($"https://www.wikidata.org/w/api.php?action=wbgetentities&ids={title}&props=claims&format=json", token);
            if (entity.RootElement.TryGetProperty("entities", out var entities)
                && entities.TryGetProperty(title, out var item) && item.TryGetProperty("claims", out var claims)
                && claims.TryGetProperty("P18", out var photos))
                foreach (var photo in photos.EnumerateArray())
                    if (photo.TryGetProperty("mainsnak", out var snak) && snak.TryGetProperty("datavalue", out var value))
                    {
                        if (Text(photo, "rank") != "deprecated" && Text(value, "value") is { Length: > 0 } file)
                            files.Add(file);
                        if (files.Count == 3) break;
                    }
        }
        else if (host == "commons.wikimedia.org") files.Add(title[5..]);
        else
        {
            using var page = await ReadAsync($"https://{host}/w/api.php?action=query&titles={Uri.EscapeDataString(title)}&redirects=1&prop=pageimages%7Cpageprops&piprop=name&pilicense=free&format=json&formatversion=2", token);
            foreach (var item in Pages(page))
            {
                if (Text(item, "pageimage") is { Length: > 0 } file) { files.Add(file); break; }
                if (item.TryGetProperty("pageprops", out var props) && Text(props, "wikibase_item") is { } qid
                    && Regex.IsMatch(qid, "^Q[1-9][0-9]*$"))
                    return await ResolveAsync("www.wikidata.org", qid, article, token);
            }
        }
        var images = new List<StoryImage>();
        foreach (var file in files.Distinct().Take(3))
        {
            if (await FileAsync(file, article, token) is { } image) images.Add(image);
        }
        return images;
    }

    private async Task<IReadOnlyList<StoryImage>> NearbyAsync(double latitude, double longitude, CancellationToken token)
    {
        // Stable stop coordinates, not every GPS fix, share the same small metadata cache.
        var coordinates = latitude.ToString("F4", CultureInfo.InvariantCulture) + "|" + longitude.ToString("F4", CultureInfo.InvariantCulture);
        var key = "nearby:" + coordinates;
        if (cache.TryGetValue(key, out StoryImageResult? cached)) return cached!.Images;
        using var nearby = await ReadAsync("https://en.wikipedia.org/w/api.php?action=query&generator=geosearch&ggscoord="
            + Uri.EscapeDataString(coordinates)
            + "&ggsradius=500&ggslimit=5&ggsnamespace=0&prop=pageimages%7Cinfo&inprop=url&piprop=name&pilicense=free&format=json&formatversion=2", token);
        var images = new List<StoryImage>();
        foreach (var item in Pages(nearby))
        {
            var title = Text(item, "title");
            var file = Text(item, "pageimage");
            var article = Text(item, "fullurl");
            if (string.IsNullOrWhiteSpace(title) || string.IsNullOrWhiteSpace(file)
                || article is null || !TryArticle(article, out var host, out _) || host != "en.wikipedia.org") continue;
            if (await FileAsync(file, article, token) is { } image)
                images.Add(image with { IsNearby = true, Caption = title + ": " + image.Caption });
            if (images.Count >= 3) break;
        }
        cache.Set(key, new StoryImageResult(images.Count == 0 ? "empty" : "ready", images),
            new MemoryCacheEntryOptions { Size = 1, AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(images.Count == 0 ? 10 : 360) });
        return images;
    }

    private async Task<StoryImage?> FileAsync(string file, string article, CancellationToken token)
    {
        var key = "file:" + file;
        if (cache.TryGetValue(key, out StoryImageResult? cached))
            return cached!.Images.FirstOrDefault() is { } found ? found with { ArticleUrl = article } : null;
        var image = await ReadFileAsync(file, article, token);
        cache.Set(key, new StoryImageResult(image is null ? "empty" : "ready", image is null ? [] : [image]),
            new MemoryCacheEntryOptions { Size = 1, AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(image is null ? 10 : 360) });
        return image;
    }

    private async Task<StoryImage?> ReadFileAsync(string file, string article, CancellationToken token)
    {
        if (file.Length > 512 || file.Contains('|')) return null;
        using var details = await ReadAsync("https://commons.wikimedia.org/w/api.php?action=query&titles="
            + Uri.EscapeDataString("File:" + file)
            + "&prop=imageinfo&iiprop=url%7Cextmetadata%7Cmime%7Csize&iiurlwidth=1000&format=json&formatversion=2", token);
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
                    || licenseUri.Scheme is not ("https" or "http") || licenseUri.Host != "creativecommons.org"
                    || !licenseUri.IsDefaultPort || licenseUri.UserInfo.Length != 0
                    || !Regex.IsMatch(licenseUri.AbsolutePath, @"^/(licenses/(by|by-sa)/(1\.0|2\.0|2\.5|3\.0|4\.0)|publicdomain/(zero|mark)/1\.0)/$")) continue;
                licenseUrl = "https://creativecommons.org" + licenseUri.AbsolutePath;
                var artist = Meta(meta, "Artist");
                var url = Text(info, "thumburl");
                if (url is null && info.TryGetProperty("width", out var width) && width.TryGetInt32(out var w) && w <= 1200
                    && info.TryGetProperty("height", out var height) && height.TryGetInt32(out var h) && h <= 1200
                    && info.TryGetProperty("size", out var size) && size.TryGetInt64(out var bytes) && bytes <= 8_000_000)
                    url = Text(info, "url");
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
        var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
        if (document.RootElement.TryGetProperty("error", out _))
        {
            document.Dispose();
            throw new HttpRequestException("Wikimedia API returned an error.");
        }
        return document;
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
            || !uri.IsDefaultPort || uri.UserInfo.Length != 0) return false;
        host = uri.Host;
        if (host == "www.wikidata.org" && uri.AbsolutePath.StartsWith("/entity/"))
        {
            title = uri.AbsolutePath[8..];
            return Regex.IsMatch(title, "^Q[1-9][0-9]*$");
        }
        if (!uri.AbsolutePath.StartsWith("/wiki/")) return false;
        title = Uri.UnescapeDataString(uri.AbsolutePath[6..]);
        return host == "www.wikidata.org" ? Regex.IsMatch(title, "^Q[1-9][0-9]*$")
            : host == "commons.wikimedia.org" ? title.StartsWith("File:") && title.Length > 5 && !title.Contains('|')
            : Regex.IsMatch(host, "^[a-z]{2,3}\\.wikipedia\\.org$") && title.Length > 0 && !title.Contains(':') && !title.Contains('|');
    }
    public void Dispose() => cache.Dispose();
}
