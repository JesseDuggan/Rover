using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class WikidataLocationContextProvider : LocationContextProviderBase
{
    private readonly IHttpClientFactory _httpClientFactory;

    public WikidataLocationContextProvider(IHttpClientFactory httpClientFactory, ILocationContextCache cache, TimeProvider timeProvider, LocationProviderOptions options)
        : base(cache, timeProvider, options)
    {
        _httpClientFactory = httpClientFactory;
    }

    public override string Name => "Wikidata";

    protected override async Task<LocationContextProviderResult> FetchAsync(LocationContextQuery query, CancellationToken cancellationToken)
    {
        var client = _httpClientFactory.CreateClient("Wikidata");
        var radiusKm = Math.Min(query.RadiusMeters / 1000d, 10).ToString("0.###", CultureInfo.InvariantCulture);
        var sparql = $$"""
            SELECT ?place ?placeLabel ?location ?distance ?instanceLabel WHERE {
              SERVICE wikibase:around {
                ?place wdt:P625 ?location .
                bd:serviceParam wikibase:center "Point({{query.UserLocation.Longitude.ToString(CultureInfo.InvariantCulture)}} {{query.UserLocation.Latitude.ToString(CultureInfo.InvariantCulture)}})"^^geo:wktLiteral .
                bd:serviceParam wikibase:radius "{{radiusKm}}" .
                bd:serviceParam wikibase:distance ?distance .
              }
              OPTIONAL { ?place wdt:P31 ?instance }
              SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
            } ORDER BY ?distance LIMIT {{Math.Clamp(Options.MaximumResults, 1, 50)}}
            """;
        var endpoint = Options.Endpoint ?? "https://query.wikidata.org/sparql";
        var url = $"{endpoint}?format=json&query={Uri.EscapeDataString(sparql)}";
        using var document = await client.GetFromJsonAsync<JsonDocument>(url, cancellationToken);
        if (document is null
            || !document.RootElement.TryGetProperty("results", out var results)
            || !results.TryGetProperty("bindings", out var bindings)
            || bindings.ValueKind != JsonValueKind.Array)
        {
            return new LocationContextProviderResult(Name, true, Array.Empty<LocationPlace>(), null, new[] { "Wikidata returned no nearby entities." }, false, 0);
        }

        var places = new List<LocationPlace>();
        foreach (var item in bindings.EnumerateArray())
        {
            var placeUri = Binding(item, "place");
            var label = Binding(item, "placeLabel");
            var point = Binding(item, "location");
            if (string.IsNullOrWhiteSpace(placeUri) || string.IsNullOrWhiteSpace(label) || string.IsNullOrWhiteSpace(point))
            {
                continue;
            }

            var coordinates = ParsePoint(point);
            if (coordinates is null)
            {
                continue;
            }

            var qid = placeUri.Split('/').Last();
            var instance = Binding(item, "instanceLabel");
            var source = Source(qid, placeUri, "Wikidata contributors", "CC0", 0.84);
            var factText = string.IsNullOrWhiteSpace(instance)
                ? $"{label} is a Wikidata-listed place near this route."
                : $"{label} is listed in Wikidata as {Article(instance)} {instance}.";
            var fact = new LocationFact($"wikidata:{qid}:instance", "structured_entity", factText, source, 0.76, true, Now);
            places.Add(Place($"wikidata-{qid}", label, coordinates, null, new[] { instance ?? "wikidata" }, null, new[] { fact }, new[] { source }, new Dictionary<string, string> { ["wikidata"] = qid }, 0.84, Now));
        }

        return new LocationContextProviderResult(Name, true, places, null, Array.Empty<string>(), false, 0);
    }

    private static string? Binding(JsonElement item, string name)
        => item.TryGetProperty(name, out var value)
            && value.TryGetProperty("value", out var text)
            && text.ValueKind == JsonValueKind.String
                ? text.GetString()
                : null;

    private static GeoLocation? ParsePoint(string value)
    {
        var text = value.Replace("Point(", string.Empty, StringComparison.OrdinalIgnoreCase).Replace(")", string.Empty);
        var parts = text.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length == 2 && double.TryParse(parts[0], NumberStyles.Float, CultureInfo.InvariantCulture, out var lng) && double.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out var lat)
            ? new GeoLocation(lat, lng)
            : null;
    }

    private static string Article(string value)
        => value.Length > 0 && "aeiou".Contains(char.ToLowerInvariant(value[0])) ? "an" : "a";
}
