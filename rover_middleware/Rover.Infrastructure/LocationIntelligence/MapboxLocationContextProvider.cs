using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class MapboxLocationContextProvider : LocationContextProviderBase, ICandidateObservationSearchProvider
{
    private readonly IHttpClientFactory _httpClientFactory;

    public MapboxLocationContextProvider(IHttpClientFactory httpClientFactory, ILocationContextCache cache, TimeProvider timeProvider, LocationProviderOptions options)
        : base(cache, timeProvider, options)
    {
        _httpClientFactory = httpClientFactory;
    }

    public override string Name => "Mapbox";

    public async Task<CandidateObservationSearchResult> SearchAsync(
        CandidateObservationQuery query,
        CancellationToken cancellationToken)
    {
        if (!Options.Enabled || string.IsNullOrWhiteSpace(Options.AccessToken))
        {
            return new CandidateObservationSearchResult(
                Name,
                Array.Empty<LocationPlace>(),
                new[] { "Mapbox business search is not configured." });
        }

        var searchText = string.Join(
            ' ',
            query.RecognizedText.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        if (searchText.Length > 256)
        {
            searchText = searchText[..256];
        }

        var proximity = FormattableString.Invariant(
            $"{query.UserLocation.Longitude},{query.UserLocation.Latitude}");
        var radiusDegrees = Math.Clamp(query.RadiusMeters / 111320d, 0.00001d, 10d)
            .ToString(CultureInfo.InvariantCulture);
        var categoryEndpoint = Options.Endpoint?.TrimEnd('/')
            ?? "https://api.mapbox.com/search/searchbox/v1/category";
        const string categorySuffix = "/category";
        var searchRoot = categoryEndpoint.EndsWith(categorySuffix, StringComparison.OrdinalIgnoreCase)
            ? categoryEndpoint[..^categorySuffix.Length]
            : "https://api.mapbox.com/search/searchbox/v1";
        var url = $"{searchRoot}/forward?q={Uri.EscapeDataString(searchText)}&access_token={Uri.EscapeDataString(Options.AccessToken)}&language=en&types=poi&limit={Math.Clamp(Options.MaximumResults, 1, 10)}&proximity={Uri.EscapeDataString(proximity)}&radius={radiusDegrees}";

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(Options.TimeoutSeconds, 2, 30)));
        var client = _httpClientFactory.CreateClient("MapboxSearch");
        using var document = await client.GetFromJsonAsync<JsonDocument>(url, timeout.Token);
        if (document is null
            || !document.RootElement.TryGetProperty("features", out var features)
            || features.ValueKind != JsonValueKind.Array)
        {
            return new CandidateObservationSearchResult(
                Name,
                Array.Empty<LocationPlace>(),
                new[] { "Mapbox business search returned no features." });
        }

        var places = features.EnumerateArray()
            .Select(feature => ParseFeature(feature, "business"))
            .Where(place => place is not null)
            .Cast<LocationPlace>()
            .Where(place => RouteMath.DistanceMeters(query.UserLocation, place.Coordinates) <= query.RadiusMeters)
            .ToArray();
        return new CandidateObservationSearchResult(Name, places, Array.Empty<string>());
    }

    protected override async Task<LocationContextProviderResult> FetchAsync(LocationContextQuery query, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(Options.AccessToken))
        {
            return new LocationContextProviderResult(Name, true, Array.Empty<LocationPlace>(), null, new[] { "Mapbox token is not configured." }, false, 0);
        }

        var client = _httpClientFactory.CreateClient("MapboxSearch");
        var categories = query.Interests.Count == 0 ? new[] { "coffee", "cafe", "restaurant", "tourist_attraction", "park" } : query.Interests.Select(NormalizeCategory).Distinct(StringComparer.OrdinalIgnoreCase).Take(6);
        var places = new List<LocationPlace>();
        foreach (var category in categories)
        {
            var proximity = FormattableString.Invariant($"{query.UserLocation.Longitude},{query.UserLocation.Latitude}");
            var radiusDegrees = Math.Clamp(query.RadiusMeters / 111320d, 0.00001d, 10d).ToString(CultureInfo.InvariantCulture);
            var url = $"{Options.Endpoint?.TrimEnd('/') ?? "https://api.mapbox.com/search/searchbox/v1/category"}/{Uri.EscapeDataString(category)}?access_token={Uri.EscapeDataString(Options.AccessToken)}&language=en&limit={Math.Clamp(Options.MaximumResults, 1, 25)}&proximity={Uri.EscapeDataString(proximity)}&radius={radiusDegrees}";
            using var document = await client.GetFromJsonAsync<JsonDocument>(url, cancellationToken);
            if (document is null || !document.RootElement.TryGetProperty("features", out var features) || features.ValueKind != JsonValueKind.Array)
            {
                continue;
            }

            foreach (var feature in features.EnumerateArray())
            {
                var place = ParseFeature(feature, category);
                if (place is not null)
                {
                    places.Add(place);
                }
            }
        }

        return new LocationContextProviderResult(Name, true, places, null, Array.Empty<string>(), false, 0);
    }

    private LocationPlace? ParseFeature(JsonElement feature, string fallbackCategory)
    {
        if (!feature.TryGetProperty("properties", out var properties)
            || !feature.TryGetProperty("geometry", out var geometry)
            || !geometry.TryGetProperty("coordinates", out var coordinates)
            || coordinates.ValueKind != JsonValueKind.Array
            || coordinates.GetArrayLength() < 2)
        {
            return null;
        }

        var name = ReadString(properties, "name");
        if (string.IsNullOrWhiteSpace(name))
        {
            return null;
        }

        var longitude = coordinates[0].GetDouble();
        var latitude = coordinates[1].GetDouble();
        var mapboxId = ReadString(properties, "mapbox_id") ?? $"mapbox-{NormalizeId(name)}";
        var fullAddress = ReadString(properties, "full_address") ?? ReadString(properties, "address");
        var categories = ReadStringArray(properties, "poi_category_ids").Concat(ReadStringArray(properties, "poi_category")).DefaultIfEmpty(fallbackCategory).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var sourceUrl = $"https://www.mapbox.com/search/?query={Uri.EscapeDataString(name)}";
        var source = Source(mapboxId, sourceUrl, "Mapbox", "Mapbox service terms", 0.78);
        var description = string.IsNullOrWhiteSpace(fullAddress)
            ? $"{name} is a nearby {categories.FirstOrDefault() ?? fallbackCategory} place."
            : $"{name} is listed near {fullAddress}.";
        var fact = new LocationFact($"mapbox:{mapboxId}:summary", "poi_summary", description, source, 0.72, true, Now);
        var providerIds = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) { ["mapbox"] = mapboxId };
        if (properties.TryGetProperty("external_ids", out var externalIds) && externalIds.ValueKind == JsonValueKind.Object)
        {
            foreach (var externalId in externalIds.EnumerateObject())
            {
                if (externalId.Value.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(externalId.Value.GetString()))
                {
                    providerIds[externalId.Name] = externalId.Value.GetString()!;
                }
            }
        }

        return Place($"mapbox-{NormalizeId(mapboxId)}", name, new GeoLocation(latitude, longitude), fullAddress, categories, description, new[] { fact }, new[] { source }, providerIds, 0.78, Now, ReadString(properties, "operational_status"));
    }

    private static string NormalizeCategory(string value)
    {
        var text = value.Trim().ToLowerInvariant();
        if (text.Contains("cake") || text.Contains("bakery")) return "bakery";
        if (text.Contains("burger")) return "burger";
        if (text.Contains("site") || text.Contains("history") || text.Contains("landmark")) return "tourist_attraction";
        if (text.Contains("tea")) return "cafe";
        if (text.Contains("coffee")) return "coffee";
        return text.Replace(' ', '_');
    }

    private static string? ReadString(JsonElement element, string name)
        => element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static IEnumerable<string> ReadStringArray(JsonElement element, string name)
        => element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Array
            ? value.EnumerateArray().Where(item => item.ValueKind == JsonValueKind.String).Select(item => item.GetString()!).Where(item => !string.IsNullOrWhiteSpace(item))
            : Array.Empty<string>();

    private static string NormalizeId(string value)
        => new(value.ToLowerInvariant().Select(character => char.IsLetterOrDigit(character) ? character : '-').ToArray());
}
