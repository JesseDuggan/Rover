using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Caching.Memory;
using Microsoft.Extensions.Logging;
using Rover.Application.Journeys;
using Rover.Application.Walks;

namespace Rover.Infrastructure.Journeys;

public sealed class EuropeanaOptions
{
    public bool Enabled { get; set; } = true;
    public string? ApiKey { get; set; }
    public TimeSpan MinimumRequestInterval { get; set; } = TimeSpan.FromSeconds(1);
}

public sealed record ArchiveResearchLead(string Subject, string Title, string Description, string SourceUrl);
public sealed record EuropeanaResult(IReadOnlyList<StoryImage> Images, IReadOnlyList<ArchiveResearchLead> Leads, bool Failed = false);

// Archive locations may describe the holding institution. Never use them as POI coordinates.
public sealed class EuropeanaArchiveClient(IHttpClientFactory clients, EuropeanaOptions options,
    TimeProvider clock, ILogger<EuropeanaArchiveClient> logger) : IDisposable
{
    private readonly MemoryCache cache = new(new MemoryCacheOptions { SizeLimit = 256 });
    private readonly SemaphoreSlim gate = new(1, 1);
    private DateTimeOffset nextRequestAt;
    private DateTimeOffset cooldownUntil;
    private static readonly EuropeanaResult Empty = new([], []);
    public bool Enabled => options.Enabled && !string.IsNullOrWhiteSpace(options.ApiKey);

    public Task<EuropeanaResult> FindPicturesAsync(string source, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (TryRecordId(source, out var id)) return SearchAsync(null, null, id, token);
        if (!Uri.TryCreate(source, UriKind.Absolute, out var uri) || !SafeHttps(uri)
            || !Regex.IsMatch(uri.Host, @"^[a-z]{2,3}\.wikipedia\.org$") || !uri.AbsolutePath.StartsWith("/wiki/"))
            return Task.FromResult(Empty);
        var subject = Uri.UnescapeDataString(uri.AbsolutePath[6..]).Replace('_', ' ');
        return ValidSubject(subject) ? SearchAsync(subject, null, null, token) : Task.FromResult(Empty);
    }

    public async Task<IReadOnlyList<ArchiveResearchLead>> FindResearchLeadsAsync(LocalRouteResearchQuery query,
        IReadOnlyList<HistoricalSubject> subjects, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        // Existing classification still enforces the selected interests, citations and route boundary.
        var skip = !Enabled ? "disabled-or-missing-key" : query.Question is not null ? "explicit-question"
            : StoryInterestPolicy.DiscoveryTypes(query.Interests).Length == 0 ? "interests"
            : string.IsNullOrWhiteSpace(query.Area.City) || query.Area.City.Length > 120 ? "missing-locality" : null;
        if (skip is not null)
        {
            logger.LogInformation("Europeana research skipped: {Reason}.", skip);
            return [];
        }
        var radius = query.AreaFirst ? Math.Clamp(query.SearchRadiusMeters, 1000, 20000) : 1000;
        var names = subjects.Select(s => (s.Name, s.Location))
            .Concat((query.PublicPlaces ?? []).Select(s => (s.Name, s.Location)))
            .Where(s => query.Segments.Any(segment => RouteMath.DistanceMeters(segment.Anchor, s.Location) <= radius))
            .Select(s => s.Name).Where(ValidResearchSubject).Distinct(StringComparer.OrdinalIgnoreCase).Take(2).ToArray();
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(TimeSpan.FromSeconds(4));
        var leads = new List<ArchiveResearchLead>();
        var attempted = 0;
        var failed = 0;
        foreach (var name in names)
        {
            try
            {
                attempted++;
                var result = await SearchAsync(name, query.Area.City, null, budget.Token, research: true);
                if (result.Failed) failed++;
                leads.AddRange(result.Leads);
            }
            catch (OperationCanceledException) when (!token.IsCancellationRequested) { failed++; break; }
            if (budget.IsCancellationRequested) break;
        }
        token.ThrowIfCancellationRequested();
        var accepted = leads.DistinctBy(x => x.SourceUrl).Take(4).ToArray();
        logger.LogInformation("Europeana research: {Subjects} local subjects; {Attempted} lookups; {Leads} leads; {Failed} unavailable.",
            names.Length, attempted, accepted.Length, failed);
        return accepted;
    }

    private async Task<EuropeanaResult> SearchAsync(string? subject, string? locality, string? id, CancellationToken token, bool research = false)
    {
        token.ThrowIfCancellationRequested();
        if (!Enabled) return Empty;
        var key = JsonSerializer.Serialize(new { subject, locality, id, research });
        if (cache.TryGetValue(key, out EuropeanaResult? cached)) return cached!;
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(TimeSpan.FromSeconds(4));
        var entered = false;
        try
        {
            await gate.WaitAsync(budget.Token);
            entered = true;
            if (cache.TryGetValue(key, out cached)) return cached!;
            if (clock.GetUtcNow() < cooldownUntil) return new([], [], true);
            var delay = nextRequestAt - clock.GetUtcNow();
            if (delay > TimeSpan.Zero) await Task.Delay(delay, budget.Token);
            nextRequestAt = clock.GetUtcNow() + options.MinimumRequestInterval;
            var query = id is not null ? "europeana_id:" + Quote(id) : "title:" + Quote(subject!);
            if (locality is not null) query += " AND where:" + Quote(locality);
            using var request = new HttpRequestMessage(HttpMethod.Get,
                "https://api.europeana.eu/record/v2/search.json?query=" + Uri.EscapeDataString(query)
                + (research ? "" : "&qf=TYPE%3AIMAGE&reusability=open&thumbnail=true")
                + "&profile=rich&rows=6");
            // Header authentication avoids credentials in URLs, caches, responses and access logs.
            request.Headers.Add("X-Api-Key", options.ApiKey!.Trim());
            using var client = clients.CreateClient("Europeana");
            using var response = await client.SendAsync(request, budget.Token);
            if (!response.IsSuccessStatusCode)
            {
                var retry = response.Headers.RetryAfter?.Delta
                    ?? (response.Headers.RetryAfter?.Date - clock.GetUtcNow()) ?? TimeSpan.FromMinutes(1);
                var seconds = response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden
                    ? Math.Max(900, retry.TotalSeconds) : Math.Max(60, retry.TotalSeconds);
                cooldownUntil = clock.GetUtcNow().AddSeconds(seconds);
                logger.LogWarning("Europeana lookup unavailable: HTTP {Status}; cooldown {Seconds}s.", (int)response.StatusCode, seconds);
                return new([], [], true);
            }
            using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(budget.Token));
            var result = Parse(document.RootElement, subject, locality, id, research);
            if (result.Failed) cooldownUntil = clock.GetUtcNow().AddMinutes(1);
            else cache.Set(key, result, new MemoryCacheEntryOptions { Size = 1,
                AbsoluteExpirationRelativeToNow = result.Images.Count + result.Leads.Count == 0 ? TimeSpan.FromMinutes(10) : TimeSpan.FromHours(6) });
            return result;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception ex) when (ex is HttpRequestException or JsonException or OperationCanceledException or InvalidOperationException or FormatException or RegexMatchTimeoutException)
        {
            if (entered) cooldownUntil = clock.GetUtcNow().AddMinutes(1);
            // Never log the request, response body (which can echo apikey), or exception message.
            logger.LogWarning("Europeana lookup unavailable: {Kind}.", ex.GetType().Name);
            return new([], [], true);
        }
        finally { if (entered) gate.Release(); }
    }

    private static EuropeanaResult Parse(JsonElement root, string? subject, string? locality, string? requestedId, bool research)
    {
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("success", out var ok) || ok.ValueKind != JsonValueKind.True
            || !root.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array) return new([], [], true);
        var images = new List<StoryImage>();
        var leads = new List<ArchiveResearchLead>();
        foreach (var item in items.EnumerateArray().Take(6))
        {
            if (item.ValueKind != JsonValueKind.Object) continue;
            var id = Text(item, "id");
            if (id is null || !Regex.IsMatch(id, @"^/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$")
                || requestedId is not null && requestedId != id) continue;
            var titles = Values(item, "title").Concat(Values(item, "dcTitleLangAware"));
            var title = titles.FirstOrDefault(value => subject is null || ContainsPhrase(value, subject));
            var description = string.Join(" ", Values(item, "dcDescription").Concat(Values(item, "dcDescriptionLangAware")).Distinct());
            if (string.IsNullOrWhiteSpace(title) || title.Length > 500
                || subject is not null && !ContainsPhrase(title, subject)) continue;
            var places = string.Join(" ", Values(item, "edmPlaceLabel").Concat(Values(item, "edmPlaceLabelLangAware"))
                .Concat(Values(item, "dctermsSpatial")));
            if (locality is not null && !ContainsPhrase(title + " " + description + " " + places, locality)) continue;
            var source = "https://www.europeana.eu/item" + id;
            // Catalogue metadata is a lead, not permission to display its media.
            // The researcher must still independently verify every narrated claim.
            if (research)
            {
                if (description.Length > 0)
                    leads.Add(new(subject ?? title, title, description[..Math.Min(700, description.Length)], source));
                continue;
            }
            if (Text(item, "type") != "IMAGE"
                || item.TryGetProperty("previewNoDistribute", out var noDistribute) && noDistribute.ValueKind != JsonValueKind.False) continue;
            var rights = Values(item, "rights").Distinct().ToArray();
            // Conflicting rights across media in a record cannot safely be assigned to its preview.
            if (rights.Length != 1 || !TryLicense(rights[0], out var license, out var licenseUrl)) continue;
            var preview = Values(item, "edmPreview").Select(Thumbnail).FirstOrDefault(x => x is not null);
            var provider = string.Join("; ", Values(item, "dataProvider").Distinct());
            var creators = string.Join("; ", Values(item, "dcCreator").Distinct());
            if (string.IsNullOrWhiteSpace(creators) && license is "CC0 1.0" or "Public domain") creators = "Creator not recorded";
            if (preview is null || string.IsNullOrWhiteSpace(provider) || string.IsNullOrWhiteSpace(creators)) continue;
            var date = Values(item, "year").FirstOrDefault(x => Regex.IsMatch(x, @"^[12][0-9]{3}$"));
            var caption = title + (date is null ? "" : " (" + date + ")");
            images.Add(new(preview, caption, creators + " - " + provider, license, licenseUrl, source, source,
                Provider: "Europeana", IsArchive: true));
            if (description.Length > 0)
                leads.Add(new(subject ?? title, title, description[..Math.Min(700, description.Length)], source));
            if (images.Count == 3) break;
        }
        return new(images.DistinctBy(x => x.SourceUrl).ToArray(), leads.DistinctBy(x => x.SourceUrl).ToArray());
    }

    public static bool TryRecordId(string source, out string id)
    {
        id = "";
        if (!Uri.TryCreate(source, UriKind.Absolute, out var uri) || !SafeHttps(uri) || uri.Host != "www.europeana.eu") return false;
        var match = Regex.Match(uri.AbsolutePath, @"^/(?:[a-z]{2}/)?item(/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+)/?$");
        if (!match.Success) return false;
        id = match.Groups[1].Value;
        return true;
    }

    private static string? Thumbnail(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || !SafeHttps(uri) || uri.Host != "api.europeana.eu") return null;
        if (Regex.IsMatch(uri.AbsolutePath, @"^/thumbnail/v3/(200|400)/[a-fA-F0-9]{32}\.jpg$") && uri.Query.Length == 0)
            return "https://api.europeana.eu" + uri.AbsolutePath.Replace("/200/", "/400/");
        if (uri.AbsolutePath != "/thumbnail/v2/url.json") return null;
        var query = Microsoft.AspNetCore.WebUtilities.QueryHelpers.ParseQuery(uri.Query);
        var original = query.TryGetValue("uri", out var resource) ? resource.ToString()
            : query.TryGetValue("url", out resource) ? resource.ToString() : "";
        if (!Uri.TryCreate(original, UriKind.Absolute, out var media) || media.Scheme is not ("http" or "https")
            || !media.IsDefaultPort || media.UserInfo.Length != 0 || media.HostNameType != UriHostNameType.Dns
            || !media.Host.Contains('.') || media.Host.EndsWith(".local", StringComparison.OrdinalIgnoreCase)
            || media.Host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase)) return null;
        // Only Europeana's cached thumbnail service reaches the app, never arbitrary institution URLs.
        return "https://api.europeana.eu/thumbnail/v2/url.json?uri=" + Uri.EscapeDataString(original) + "&size=w400&type=IMAGE";
    }

    private static bool TryLicense(string raw, out string label, out string url)
    {
        label = url = "";
        if (!Uri.TryCreate(raw, UriKind.Absolute, out var uri) || uri.Scheme is not ("http" or "https")
            || uri.Host != "creativecommons.org" || !uri.IsDefaultPort || uri.UserInfo.Length != 0) return false;
        var match = Regex.Match(uri.AbsolutePath, @"^/licenses/(by|by-sa)/(1\.0|2\.0|2\.5|3\.0|4\.0)/$");
        if (match.Success) label = "CC " + match.Groups[1].Value.ToUpperInvariant() + " " + match.Groups[2].Value;
        else if (uri.AbsolutePath == "/publicdomain/zero/1.0/") label = "CC0 1.0";
        else if (uri.AbsolutePath == "/publicdomain/mark/1.0/") label = "Public domain";
        else return false;
        url = "https://creativecommons.org" + uri.AbsolutePath;
        return true;
    }

    private static bool ValidSubject(string subject) => subject.Length is >= 8 and <= 160 &&
        !subject.Contains(':') && Regex.Matches(subject, @"[\p{L}\p{N}]+").Count >= 2;
    // A geocoded subject plus a required locality can disambiguate single-word names.
    private static bool ValidResearchSubject(string subject) => subject.Length is >= 4 and <= 160 &&
        !subject.Contains(':') && Regex.IsMatch(subject, @"\p{L}");
    private static string Quote(string text) => "\"" + text.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    private static bool SafeHttps(Uri uri) => uri.Scheme == "https" && uri.IsDefaultPort && uri.UserInfo.Length == 0;
    private static string Normalize(string value) => Regex.Replace(value.ToLowerInvariant(), @"[^\p{L}\p{N}]+", " ").Trim();
    private static bool ContainsPhrase(string text, string phrase) =>
        (" " + Normalize(text) + " ").Contains(" " + Normalize(phrase) + " ", StringComparison.Ordinal);
    private static string? Text(JsonElement item, string key) => item.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
    private static IEnumerable<string> Values(JsonElement item, string key) => item.TryGetProperty(key, out var value) ? Strings(value, 0).Take(8) : [];
    private static IEnumerable<string> Strings(JsonElement value, int depth)
    {
        if (depth > 3) yield break;
        if (value.ValueKind == JsonValueKind.String)
        {
            var raw = value.GetString() ?? "";
            if (raw.Length > 8192) yield break;
            var text = WebUtility.HtmlDecode(Regex.Replace(raw, "<[^>]*>", "", RegexOptions.None, TimeSpan.FromMilliseconds(100))).Trim();
            if (text.Length is > 0 and <= 2048) yield return text;
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var entry in value.EnumerateArray().Take(8))
                foreach (var text in Strings(entry, depth + 1)) yield return text;
        else if (value.ValueKind == JsonValueKind.Object)
            foreach (var entry in value.EnumerateObject().Take(8))
                foreach (var text in Strings(entry.Value, depth + 1)) yield return text;
    }

    public void Dispose() { cache.Dispose(); gate.Dispose(); }
}
