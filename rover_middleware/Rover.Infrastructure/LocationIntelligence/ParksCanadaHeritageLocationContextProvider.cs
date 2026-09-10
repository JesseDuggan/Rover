using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class ParksCanadaHeritageLocationContextProvider : LocationContextProviderBase
{
    private const string DefaultEndpoint = "https://services2.arcgis.com/wCOMu5IS7YdSyPNx/arcgis/rest/services/Interest_Point_Interet_APCA_OpenOuvert/FeatureServer/0";
    private const string DatasetPageUrl = "https://open.canada.ca/data/en/dataset/cf5c266c-3a6a-4a3b-aed1-2ddd6e49d5e6";
    private static readonly HashSet<string> ApprovedHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "services2.arcgis.com"
    };
    private static readonly string[] HeritageTerms =
    [
        "archive", "archaeolog", "cemetery", "cultural", "fort", "heritage",
        "historic", "history", "lighthouse", "memorial", "monument", "museum",
        "railway", "ruin"
    ];

    private readonly IHttpClientFactory _httpClientFactory;

    public ParksCanadaHeritageLocationContextProvider(
        IHttpClientFactory httpClientFactory,
        ILocationContextCache cache,
        TimeProvider timeProvider,
        LocationProviderOptions options)
        : base(cache, timeProvider, options)
    {
        _httpClientFactory = httpClientFactory;
    }

    public override string Name => "ParksCanadaHeritage";

    protected override async Task<LocationContextProviderResult> FetchAsync(
        LocationContextQuery query,
        CancellationToken cancellationToken)
    {
        var endpoint = Options.Endpoint ?? DefaultEndpoint;
        if (!TryGetApprovedEndpoint(endpoint, out var approvedEndpoint))
        {
            return Unavailable("Parks Canada heritage endpoint is not on the approved source allowlist.");
        }

        var requestUri = BuildQueryUri(approvedEndpoint, query);
        try
        {
            var client = _httpClientFactory.CreateClient("ParksCanadaHeritage");
            using var response = await client.GetAsync(requestUri, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                return Unavailable($"Parks Canada heritage service returned {(int)response.StatusCode}.");
            }

            using var document = await response.Content.ReadFromJsonAsync<JsonDocument>(cancellationToken);
            if (document is null
                || !document.RootElement.TryGetProperty("features", out var features)
                || features.ValueKind != JsonValueKind.Array)
            {
                return Unavailable("Parks Canada heritage service returned no feature collection.");
            }

            var places = features.EnumerateArray()
                .Select(ParseFeature)
                .Where(place => place is not null)
                .Cast<LocationPlace>()
                .Take(Math.Clamp(Options.MaximumResults, 1, 50))
                .ToArray();
            return new LocationContextProviderResult(Name, true, places, null, Array.Empty<string>(), false, 0);
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException)
        {
            return Unavailable("Parks Canada heritage service is temporarily unavailable.");
        }
    }

    private LocationPlace? ParseFeature(JsonElement feature)
    {
        if (!feature.TryGetProperty("properties", out var properties)
            || !feature.TryGetProperty("geometry", out var geometry)
            || !geometry.TryGetProperty("coordinates", out var coordinates)
            || coordinates.ValueKind != JsonValueKind.Array
            || coordinates.GetArrayLength() < 2)
        {
            return null;
        }

        var name = Text(properties, "Name_e");
        var description = Text(properties, "Descr_e");
        if (string.IsNullOrWhiteSpace(name) || !IsHeritageRelevant(name, description))
        {
            return null;
        }

        if (coordinates[0].ValueKind != JsonValueKind.Number
            || coordinates[1].ValueKind != JsonValueKind.Number)
        {
            return null;
        }

        var longitude = coordinates[0].GetDouble();
        var latitude = coordinates[1].GetDouble();
        var recordId = Identifier(properties, "OBJECTID") ?? Identifier(feature, "id");
        if (string.IsNullOrWhiteSpace(recordId))
        {
            return null;
        }
        var source = Source(
            recordId,
            DatasetPageUrl,
            "Parks Canada Open Data",
            "Open Government Licence - Canada",
            0.93) with
        {
            SourceTitle = "Parks Canada Interest Points",
            ExpiresUtc = Now.AddMinutes(Math.Max(1, Options.CacheMinutes))
        };
        var factText = string.IsNullOrWhiteSpace(description)
            ? $"Parks Canada maps {name} as a heritage-related point of interest."
            : $"Parks Canada describes {name} as {description.Trim().TrimEnd('.')}.";
        var fact = new LocationFact(
            $"parks-canada:{recordId}:description",
            "authoritative_heritage_description",
            factText,
            source,
            0.91,
            true,
            Now);

        return Place(
            $"parks-canada-{recordId}",
            name,
            new GeoLocation(latitude, longitude),
            null,
            new[] { "heritage", "local history", "parks canada" },
            description,
            new[] { fact },
            new[] { source },
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["parks_canada"] = recordId
            },
            0.93,
            Now);
    }

    private LocationContextProviderResult Unavailable(string warning) =>
        new(Name, true, Array.Empty<LocationPlace>(), null, new[] { warning }, false, 0);

    private Uri BuildQueryUri(Uri endpoint, LocationContextQuery query)
    {
        var parameters = new Dictionary<string, string>
        {
            ["f"] = "geojson",
            ["where"] = HeritageWhereClause(),
            ["geometry"] = string.Create(CultureInfo.InvariantCulture, $"{query.UserLocation.Longitude},{query.UserLocation.Latitude}"),
            ["geometryType"] = "esriGeometryPoint",
            ["inSR"] = "4326",
            ["spatialRel"] = "esriSpatialRelIntersects",
            ["distance"] = Math.Min(query.RadiusMeters, 5000).ToString(CultureInfo.InvariantCulture),
            ["units"] = "esriSRUnit_Meter",
            ["outFields"] = "OBJECTID,Name_e,Descr_e,Principal_type,D_Source,D_Source_Code",
            ["returnGeometry"] = "true",
            ["outSR"] = "4326",
            ["orderByFields"] = "OBJECTID",
            ["resultRecordCount"] = Math.Clamp(Options.MaximumResults, 1, 50).ToString(CultureInfo.InvariantCulture)
        };
        var queryString = string.Join("&", parameters.Select(pair => $"{Uri.EscapeDataString(pair.Key)}={Uri.EscapeDataString(pair.Value)}"));
        return new Uri($"{endpoint.AbsoluteUri.TrimEnd('/')}/query?{queryString}");
    }

    private static bool TryGetApprovedEndpoint(string value, out Uri endpoint)
    {
        if (Uri.TryCreate(value, UriKind.Absolute, out var parsed)
            && parsed.Scheme == Uri.UriSchemeHttps
            && ApprovedHosts.Contains(parsed.Host))
        {
            endpoint = parsed;
            return true;
        }

        endpoint = null!;
        return false;
    }

    private static bool IsHeritageRelevant(string name, string? description)
    {
        var searchable = $"{name} {description}";
        return HeritageTerms.Any(term => searchable.Contains(term, StringComparison.OrdinalIgnoreCase));
    }

    private static string HeritageWhereClause()
    {
        var predicates = HeritageTerms.Select(term =>
        {
            var value = term.ToUpperInvariant().Replace("'", "''", StringComparison.Ordinal);
            return $"UPPER(Name_e) LIKE '%{value}%' OR UPPER(Descr_e) LIKE '%{value}%'";
        });
        return $"Name_e IS NOT NULL AND ({string.Join(" OR ", predicates)})";
    }

    private static string? Text(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static string? Identifier(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value)
            ? value.ValueKind switch
            {
                JsonValueKind.String => value.GetString(),
                JsonValueKind.Number => value.GetRawText(),
                _ => null
            }
            : null;
}
