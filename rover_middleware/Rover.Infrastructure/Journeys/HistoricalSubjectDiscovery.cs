using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Caching.Memory;
using Rover.Application.Journeys;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Journeys;

public sealed record HistoricalSubject(string Name, string EntityUrl, GeoLocation Location);

// Discovery records identify subjects, not evidence for a narrated historical claim.
public sealed class HistoricalSubjectDiscovery(IHttpClientFactory clients) : IDisposable
{
    private readonly MemoryCache cache = new(new MemoryCacheOptions { SizeLimit = 256 });
    private readonly SemaphoreSlim gate = new(1, 1);

    public async Task<IReadOnlyList<HistoricalSubject>> FindAsync(LocalRouteResearchQuery query, CancellationToken token)
    {
        var types = StoryInterestPolicy.DiscoveryTypes(query.Interests);
        if (types.Length == 0 || query.Question is not null || query.Segments.Count == 0) return [];
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(TimeSpan.FromSeconds(6));
        var results = new List<HistoricalSubject>();
        var radius = query.AreaFirst ? Math.Clamp(query.SearchRadiusMeters, 1000, 20000) : 1000;
        try
        {
            // Sample the route, never transmit a full trace or a user identifier.
            foreach (var segment in query.Segments.Where((_, i) => i % Math.Max(1, query.Segments.Count / 2) == 0).Take(2))
            {
                var lat = Math.Round(segment.Anchor.Latitude, 3);
                var lon = Math.Round(segment.Anchor.Longitude, 3);
                if (!double.IsFinite(lat) || !double.IsFinite(lon) || Math.Abs(lat) > 90 || Math.Abs(lon) > 180) continue;
                var key = FormattableString.Invariant($"{lat}|{lon}|{radius}|{string.Join(',', types)}");
                await gate.WaitAsync(budget.Token);
                try
                {
                    if (!cache.TryGetValue(key, out HistoricalSubject[]? subjects))
                    {
                        var sparql = FormattableString.Invariant($$"""
                            SELECT DISTINCT ?place ?placeLabel ?location WHERE {
                              SERVICE wikibase:around {
                                ?place wdt:P625 ?location .
                                bd:serviceParam wikibase:center "Point({{lon}} {{lat}})"^^geo:wktLiteral .
                                bd:serviceParam wikibase:radius "{{(radius + 100) / 1000d}}" .
                              }
                              VALUES ?type { {{string.Join(' ', types.Select(t => "wd:" + t))}} }
                              ?place wdt:P31/wdt:P279* ?type .
                              SERVICE wikibase:label { bd:serviceParam wikibase:language "en" . }
                            } LIMIT 24
                            """);
                        using var client = clients.CreateClient("HistoricalDiscovery");
                        using var response = await client.GetAsync(
                            "https://query.wikidata.org/sparql?format=json&query=" + Uri.EscapeDataString(sparql), budget.Token);
                        if (!response.IsSuccessStatusCode)
                        {
                            cache.Set(key, Array.Empty<HistoricalSubject>(), new MemoryCacheEntryOptions
                                { Size = 1, AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(1) });
                            continue;
                        }
                        using var document = await response.Content.ReadFromJsonAsync<JsonDocument>(cancellationToken: budget.Token);
                        subjects = document is null ? [] : Parse(document).ToArray();
                        cache.Set(key, subjects, new MemoryCacheEntryOptions { Size = 1,
                            AbsoluteExpirationRelativeToNow = subjects.Length == 0 ? TimeSpan.FromMinutes(10) : TimeSpan.FromHours(6) });
                    }
                    results.AddRange(subjects ?? []);
                }
                finally { gate.Release(); }
            }
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { }
        catch (HttpRequestException) { }
        catch (JsonException) { }
        token.ThrowIfCancellationRequested();
        return results.Where(subject => query.Segments.Any(s => RouteMath.DistanceMeters(s.Anchor, subject.Location) <= radius))
            .DistinctBy(s => s.EntityUrl).Take(12).ToArray();
    }

    internal static IEnumerable<HistoricalSubject> Parse(JsonDocument document)
    {
        if (document.RootElement.ValueKind != JsonValueKind.Object || !document.RootElement.TryGetProperty("results", out var results) || results.ValueKind != JsonValueKind.Object ||
            !results.TryGetProperty("bindings", out var bindings) || bindings.ValueKind != JsonValueKind.Array) yield break;
        foreach (var row in bindings.EnumerateArray())
        {
            if (row.ValueKind != JsonValueKind.Object) continue;
            string? Value(string key) => row.TryGetProperty(key, out var item) && item.ValueKind == JsonValueKind.Object &&
                item.TryGetProperty("value", out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
            var entity = Regex.Match(Value("place") ?? "", @"^https?://www\.wikidata\.org/entity/(Q[1-9][0-9]*)$");
            var point = Regex.Match(Value("location") ?? "", @"^Point\((-?[0-9]+(?:\.[0-9]+)?) (-?[0-9]+(?:\.[0-9]+)?)\)$");
            var name = Value("placeLabel");
            if (!entity.Success || !point.Success || string.IsNullOrWhiteSpace(name) || name.Length > 160 ||
                name == entity.Groups[1].Value ||
                !double.TryParse(point.Groups[1].Value, CultureInfo.InvariantCulture, out var lon) ||
                !double.TryParse(point.Groups[2].Value, CultureInfo.InvariantCulture, out var lat) ||
                !double.IsFinite(lat) || !double.IsFinite(lon) || Math.Abs(lat) > 90 || Math.Abs(lon) > 180) continue;
            yield return new(name, "https://www.wikidata.org/wiki/" + entity.Groups[1].Value, new(lat, lon));
        }
    }

    public void Dispose() { cache.Dispose(); gate.Dispose(); }
}
