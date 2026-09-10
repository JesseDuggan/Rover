using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class OpenStreetMapLocationContextProvider : LocationContextProviderBase
{
    private static readonly SemaphoreSlim OverpassGate = new(1, 1);
    private readonly IHttpClientFactory _httpClientFactory;

    public OpenStreetMapLocationContextProvider(IHttpClientFactory httpClientFactory, ILocationContextCache cache, TimeProvider timeProvider, LocationProviderOptions options)
        : base(cache, timeProvider, options)
    {
        _httpClientFactory = httpClientFactory;
    }

    public override string Name => "OpenStreetMap";

    protected override async Task<LocationContextProviderResult> FetchAsync(LocationContextQuery query, CancellationToken cancellationToken)
    {
        await OverpassGate.WaitAsync(cancellationToken);
        try
        {
            var client = _httpClientFactory.CreateClient("Overpass");
            var radius = Math.Min(query.RadiusMeters, 5000).ToString(CultureInfo.InvariantCulture);
            var lat = query.UserLocation.Latitude.ToString(CultureInfo.InvariantCulture);
            var lng = query.UserLocation.Longitude.ToString(CultureInfo.InvariantCulture);
            var overpass = $$"""
                [out:json][timeout:{{Math.Clamp(Options.TimeoutSeconds, 2, 25)}}];
                (
                  nwr(around:{{radius}},{{lat}},{{lng}})["name"]["amenity"];
                  nwr(around:{{radius}},{{lat}},{{lng}})["name"]["tourism"];
                  nwr(around:{{radius}},{{lat}},{{lng}})["name"]["historic"];
                  nwr(around:{{radius}},{{lat}},{{lng}})["name"]["leisure"="park"];
                );
                out center tags {{Math.Clamp(Options.MaximumResults, 1, 50)}};
                """;
            var endpoint = Options.Endpoint ?? "https://overpass-api.de/api/interpreter";
            using var response = await client.PostAsync(endpoint, new FormUrlEncodedContent(new Dictionary<string, string> { ["data"] = overpass }), cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return new LocationContextProviderResult(Name, true, Array.Empty<LocationPlace>(), null, new[] { $"OpenStreetMap/Overpass returned {(int)response.StatusCode}." }, false, 0);
            }

            using var document = await response.Content.ReadFromJsonAsync<JsonDocument>(cancellationToken);
            if (document is null || !document.RootElement.TryGetProperty("elements", out var elements) || elements.ValueKind != JsonValueKind.Array)
            {
                return new LocationContextProviderResult(Name, true, Array.Empty<LocationPlace>(), null, new[] { "OpenStreetMap returned no elements." }, false, 0);
            }

            var places = new List<LocationPlace>();
            foreach (var element in elements.EnumerateArray())
            {
                var place = ParseElement(element);
                if (place is not null)
                {
                    places.Add(place);
                }
            }

            return new LocationContextProviderResult(Name, true, places, null, Array.Empty<string>(), false, 0);
        }
        finally
        {
            OverpassGate.Release();
        }
    }

    private LocationPlace? ParseElement(JsonElement element)
    {
        if (!element.TryGetProperty("tags", out var tags) || !tags.TryGetProperty("name", out var nameElement))
        {
            return null;
        }

        var name = nameElement.GetString();
        if (string.IsNullOrWhiteSpace(name))
        {
            return null;
        }

        double? lat = ReadNumber(element, "lat") ?? ReadNestedNumber(element, "center", "lat");
        double? lng = ReadNumber(element, "lon") ?? ReadNestedNumber(element, "center", "lon");
        if (lat is null || lng is null)
        {
            return null;
        }

        var type = element.GetProperty("type").GetString() ?? "osm";
        var id = element.GetProperty("id").GetRawText();
        var osmId = $"{type}/{id}";
        var category = ReadString(tags, "amenity") ?? ReadString(tags, "tourism") ?? ReadString(tags, "historic") ?? ReadString(tags, "leisure") ?? "openstreetmap";
        var address = BuildAddress(tags);
        var sourceUrl = $"https://www.openstreetmap.org/{type}/{id}";
        var source = Source(osmId, sourceUrl, "OpenStreetMap contributors", "ODbL", 0.76);
        var fact = new LocationFact($"osm:{type}:{id}:tags", "map_tags", $"{name} is mapped in OpenStreetMap as {category.Replace('_', ' ')}.", source, 0.68, true, Now);
        var providerIds = new Dictionary<string, string> { ["osm"] = osmId };
        var wikidata = ReadString(tags, "wikidata");
        if (!string.IsNullOrWhiteSpace(wikidata))
        {
            providerIds["wikidata"] = wikidata;
        }

        return Place($"osm-{type}-{id}", name, new GeoLocation(lat.Value, lng.Value), address, new[] { category }, null, new[] { fact }, new[] { source }, providerIds, 0.76, Now, ReadString(tags, "opening_hours"), ReadString(tags, "wheelchair"));
    }

    private static string? BuildAddress(JsonElement tags)
    {
        var street = ReadString(tags, "addr:street");
        var number = ReadString(tags, "addr:housenumber");
        var city = ReadString(tags, "addr:city");
        var parts = new[] { $"{number} {street}".Trim(), city }.Where(part => !string.IsNullOrWhiteSpace(part)).ToArray();
        return parts.Length == 0 ? null : string.Join(", ", parts);
    }

    private static string? ReadString(JsonElement element, string name)
        => element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static double? ReadNumber(JsonElement element, string name)
        => element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number ? value.GetDouble() : null;

    private static double? ReadNestedNumber(JsonElement element, string container, string name)
        => element.TryGetProperty(container, out var nested) ? ReadNumber(nested, name) : null;
}
