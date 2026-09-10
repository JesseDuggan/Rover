using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class WikipediaLocationContextProvider : LocationContextProviderBase
{
    private readonly IHttpClientFactory _httpClientFactory;

    public WikipediaLocationContextProvider(IHttpClientFactory httpClientFactory, ILocationContextCache cache, TimeProvider timeProvider, LocationProviderOptions options)
        : base(cache, timeProvider, options)
    {
        _httpClientFactory = httpClientFactory;
    }

    public override string Name => "Wikipedia";

    protected override async Task<LocationContextProviderResult> FetchAsync(LocationContextQuery query, CancellationToken cancellationToken)
    {
        var client = _httpClientFactory.CreateClient("Wikipedia");
        var endpoint = Options.Endpoint ?? "https://en.wikipedia.org/w/api.php";
        var url = $"{endpoint}?action=query&list=geosearch&gscoord={query.UserLocation.Latitude}%7C{query.UserLocation.Longitude}&gsradius={Math.Min(query.RadiusMeters, 10000)}&gslimit={Math.Clamp(Options.MaximumResults, 1, 50)}&format=json";
        using var document = await client.GetFromJsonAsync<JsonDocument>(url, cancellationToken);
        if (document is null
            || !document.RootElement.TryGetProperty("query", out var queryElement)
            || !queryElement.TryGetProperty("geosearch", out var results)
            || results.ValueKind != JsonValueKind.Array)
        {
            return new LocationContextProviderResult(Name, true, Array.Empty<LocationPlace>(), null, new[] { "Wikipedia returned no geosearch results." }, false, 0);
        }

        var places = new List<LocationPlace>();
        var warnings = new List<string>();
        var nearby = results.EnumerateArray().ToArray();
        var details = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        var pageIds = nearby
            .Where(item => item.TryGetProperty("pageid", out _))
            .Select(item => item.GetProperty("pageid").GetInt32().ToString())
            .ToArray();
        if (pageIds.Length > 0)
        {
            var detailsUrl = $"{endpoint}?action=query&pageids={string.Join("%7C", pageIds)}&prop=extracts%7Cpageprops%7Cinfo%7Cpageimages&inprop=url&exintro=1&explaintext=1&exchars=1200&pithumbsize=640&format=json&formatversion=2";
            try
            {
                using var detailDocument = await client.GetFromJsonAsync<JsonDocument>(detailsUrl, cancellationToken);
                if (detailDocument is not null
                    && detailDocument.RootElement.TryGetProperty("query", out var detailQuery)
                    && detailQuery.TryGetProperty("pages", out var pages))
                {
                    foreach (var page in EnumeratePages(pages))
                    {
                        if (page.TryGetProperty("pageid", out var id))
                        {
                            details[id.GetInt32().ToString()] = page.Clone();
                        }
                    }
                }
            }
            catch (Exception exception) when (exception is HttpRequestException or JsonException)
            {
                warnings.Add("Wikipedia page enrichment failed; nearby geosearch results were retained.");
            }
        }

        foreach (var item in nearby)
        {
            var title = item.GetProperty("title").GetString();
            if (string.IsNullOrWhiteSpace(title))
            {
                continue;
            }

            var pageId = item.GetProperty("pageid").GetInt32().ToString();
            var lat = item.GetProperty("lat").GetDouble();
            var lng = item.GetProperty("lon").GetDouble();
            var urlTitle = title.Replace(' ', '_');
            details.TryGetValue(pageId, out var detail);
            var sourceUrl = Text(detail, "fullurl") ?? $"https://en.wikipedia.org/wiki/{Uri.EscapeDataString(urlTitle)}";
            var source = Source(pageId, sourceUrl, "Wikipedia contributors", "CC BY-SA", 0.86) with
            {
                SourceTitle = title,
                ExpiresUtc = Now.AddMinutes(Math.Max(1, Options.CacheMinutes))
            };
            var facts = new List<LocationFact>
            {
                new($"wikipedia:{pageId}:nearby", "encyclopedic_nearby", $"{title} has a geotagged Wikipedia article near this walk.", source, 0.78, true, Now)
            };
            var extract = Text(detail, "extract");
            if (!string.IsNullOrWhiteSpace(extract))
            {
                facts.Add(new LocationFact($"wikipedia:{pageId}:summary", "encyclopedic_summary", extract, source, 0.86, true, Now));
            }

            var providerIds = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["wikipedia"] = pageId };
            var wikidataQid = detail.ValueKind == JsonValueKind.Object
                && detail.TryGetProperty("pageprops", out var pageProps)
                    ? Text(pageProps, "wikibase_item")
                    : null;
            if (!string.IsNullOrWhiteSpace(wikidataQid))
            {
                providerIds["wikidata"] = wikidataQid;
            }

            var place = Place($"wikipedia-{pageId}", title, new GeoLocation(lat, lng), null, new[] { "wikipedia", "local context" }, extract, facts, new[] { source }, providerIds, 0.86, Now);
            var thumbnail = detail.ValueKind == JsonValueKind.Object && detail.TryGetProperty("thumbnail", out var thumbnailElement)
                ? Text(thumbnailElement, "source")
                : null;
            places.Add(string.IsNullOrWhiteSpace(thumbnail)
                ? place
                : place with { ImageReferences = new[] { new LocationImageReference(thumbnail, title, source) } });
        }

        return new LocationContextProviderResult(Name, true, places, null, warnings, false, 0);
    }

    private static IEnumerable<JsonElement> EnumeratePages(JsonElement pages)
        => pages.ValueKind switch
        {
            JsonValueKind.Array => pages.EnumerateArray().ToArray(),
            JsonValueKind.Object => pages.EnumerateObject().Select(property => property.Value).ToArray(),
            _ => Array.Empty<JsonElement>()
        };

    private static string? Text(JsonElement item, string property)
        => item.ValueKind == JsonValueKind.Object
            && item.TryGetProperty(property, out var value)
            && value.ValueKind == JsonValueKind.String
                ? value.GetString()
                : null;
}
