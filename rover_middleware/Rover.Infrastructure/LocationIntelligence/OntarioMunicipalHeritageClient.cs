using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class OntarioMunicipalHeritageClient(
    IHttpClientFactory clients, ILocationContextCache cache, TimeProvider clock, IOntarioFieldTestRecorder recorder)
{
    private static readonly SemaphoreSlim[] Gates = Enumerable.Range(0, 32).Select(_ => new SemaphoreSlim(1)).ToArray();
    // Reviewed municipal services only. No user-supplied URL is fetched.
    public static bool ApprovedEndpoint(string value) => value is
        "https://services.arcgis.com/rYz782eMbySr2srL/arcgis/rest/services/Heritage_Properties/FeatureServer/0" or
        "https://gis.toronto.ca/arcgis/rest/services/cot_geospatial11/FeatureServer/56" or
        "https://api.milton.ca/arcgis/rest/services/Datasets/HeritageProperties/MapServer/0";

    public async Task<LocationContextProviderResult> FindAsync(string marketId, OntarioMarketOptions market,
        OntarioMunicipalDataset dataset, LocationContextQuery query, CancellationToken token)
    {
        var name = $"OntarioMunicipal:{marketId}:{dataset.Id}";
        if (!dataset.Enabled) return new(name, false, [], null, [], false, 0);
        if (!ApprovedEndpoint(dataset.Endpoint) || !Https(dataset.CatalogUrl) || !Https(dataset.LicenseUrl)
            || string.IsNullOrWhiteSpace(dataset.Attribution) || !market.HasValidGeography)
            return new(name, true, [], null, ["Municipal source configuration is not approved."], false, 0);
        var fields = new[] { "OBJECTID", dataset.NameField, dataset.StatusField, dataset.DescriptionField }
            .Concat(dataset.AddressFields).Where(s => s.Length > 0).Distinct().ToArray();
        if (fields.Any(field => !Regex.IsMatch(field, "^[A-Za-z_][A-Za-z0-9_]*$")))
            return new(name, true, [], null, ["Municipal source field mapping is invalid."], false, 0);
        var key = "ontario-municipal-v2:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
            JsonSerializer.Serialize(new { marketId, market.GeographicProfileId, market.City, market.Center,
                market.SearchRadiusMeters, market.Areas, dataset }))));
        var gate = Gates[(uint)StringComparer.Ordinal.GetHashCode(key) % (uint)Gates.Length];
        await gate.WaitAsync(token);
        try
        {
            if (cache.TryGet<LocationContextProviderResult>(key, out var cached) && cached is not null)
                return Nearby(cached with { CacheHit = true }, market, query);
            var timer = Stopwatch.StartNew();
            var places = new List<LocationPlace>();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            var warnings = new List<string>();
            var discovered = 0;
            var excluded = 0;
            var duplicates = 0;
            var failed = false;
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
            budget.CancelAfter(TimeSpan.FromSeconds(8));
            try
            {
                var limit = Math.Clamp(dataset.MaximumRecords, 1, 2000);
                // Preserve priority downtown coverage even if the larger regional catalogue hits its record budget.
                IEnumerable<OntarioTestArea?> queryAreas = market.Areas.Where(area => area.IsValid).Take(8);
                if (market.Center is not null) queryAreas = queryAreas.Append(null);
                foreach (var area in queryAreas)
                {
                    for (var offset = 0; offset < limit; offset += 200)
                    {
                        var parameters = new Dictionary<string, string>
                        {
                            ["f"] = "json", ["where"] = dataset.Where, ["outFields"] = string.Join(',', fields),
                            ["inSR"] = "4326", ["outSR"] = "4326",
                            ["spatialRel"] = "esriSpatialRelIntersects", ["returnGeometry"] = "true",
                            ["orderByFields"] = "OBJECTID ASC", ["resultOffset"] = offset.ToString(CultureInfo.InvariantCulture),
                            ["resultRecordCount"] = Math.Min(200, limit - offset).ToString(CultureInfo.InvariantCulture)
                        };
                        if (area is null && market.Center is { } center)
                        {
                            parameters["geometry"] = string.Create(CultureInfo.InvariantCulture, $"{center.Longitude},{center.Latitude}");
                            parameters["geometryType"] = "esriGeometryPoint";
                            parameters["distance"] = market.SearchRadiusMeters.ToString(CultureInfo.InvariantCulture);
                            parameters["units"] = "esriSRUnit_Meter";
                        }
                        else
                        {
                            parameters["geometry"] = string.Create(CultureInfo.InvariantCulture, $"{area!.West},{area.South},{area.East},{area.North}");
                            parameters["geometryType"] = "esriGeometryEnvelope";
                        }
                        var url = dataset.Endpoint + "/query?" + string.Join('&', parameters.Select(p =>
                            Uri.EscapeDataString(p.Key) + "=" + Uri.EscapeDataString(p.Value)));
                        using var response = await clients.CreateClient("OntarioMunicipal").GetAsync(url, budget.Token);
                        response.EnsureSuccessStatusCode();
                        using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(budget.Token));
                        var root = document.RootElement;
                        if (root.TryGetProperty("error", out _) || !root.TryGetProperty("features", out var features)
                            || features.ValueKind != JsonValueKind.Array || !IsWgs84(root))
                            throw new JsonException("Expected WGS84 point features.");
                        foreach (var feature in features.EnumerateArray())
                        {
                            discovered++;
                            var place = Parse(feature, name, market, dataset);
                            if (place is null) { excluded++; continue; }
                            if (!ids.Add(place.CanonicalId) || places.Any(existing => SameSite(existing, place)))
                            { duplicates++; continue; }
                            places.Add(place);
                        }
                        var more = root.TryGetProperty("exceededTransferLimit", out var exceeded) && exceeded.ValueKind == JsonValueKind.True;
                        if (!more) break;
                        if (features.GetArrayLength() == 0 || offset + 200 >= limit)
                        { warnings.Add("Municipal results truncated at the configured record budget."); break; }
                    }
                }
            }
            catch (Exception error) when (error is HttpRequestException or JsonException or InvalidOperationException or FormatException ||
                error is OperationCanceledException && !token.IsCancellationRequested)
            {
                failed = true;
                warnings.Add("Municipal heritage temporarily unavailable; other place sources remain available.");
            }
            token.ThrowIfCancellationRequested();
            var result = new LocationContextProviderResult(name, true, places, null, warnings, false, timer.ElapsedMilliseconds);
            // A short negative cache prevents a tester group hammering a failing municipal service.
            cache.Set(key, result, failed ? TimeSpan.FromSeconds(30) : TimeSpan.FromMinutes(Math.Clamp(dataset.CacheMinutes, 1, 1440)));
            recorder.Record(new(marketId, "municipal-discovery", failed ? "partial-or-unavailable" : "complete",
                timer.ElapsedMilliseconds, discovered, places.Count, 0, excluded, duplicates, dataset.Id,
                GeographicProfileId: market.GeographicProfileId));
            return Nearby(result, market, query);
        }
        finally { gate.Release(); }
    }

    private LocationPlace? Parse(JsonElement feature, string provider, OntarioMarketOptions market, OntarioMunicipalDataset dataset)
    {
        if (!feature.TryGetProperty("attributes", out var fields) || fields.ValueKind != JsonValueKind.Object
            || !feature.TryGetProperty("geometry", out var geometry) || geometry.ValueKind != JsonValueKind.Object
            || !geometry.TryGetProperty("x", out var x) || !geometry.TryGetProperty("y", out var y)
            || x.ValueKind != JsonValueKind.Number || y.ValueKind != JsonValueKind.Number
            || !x.TryGetDouble(out var lon) || !y.TryGetDouble(out var lat)) return null;
        var point = new GeoLocation(lat, lon);
        if (!market.Contains(point)) return null;
        var id = Text(fields, "OBJECTID");
        if (!long.TryParse(id, NumberStyles.None, CultureInfo.InvariantCulture, out var numericId) || numericId < 0) return null;
        var address = string.Join(' ', dataset.AddressFields.Select(field => Text(fields, field)).Where(s => s.Length > 0));
        var name = Text(fields, dataset.NameField);
        if (name.Length == 0) name = address;
        if (name.Length == 0) return null;
        var status = Text(fields, dataset.StatusField);
        var description = Text(fields, dataset.DescriptionField);
        var now = clock.GetUtcNow();
        var source = new LocationSource(provider, id, dataset.Endpoint + "/query?f=pjson&objectIds=" + id + "&outFields=*&outSR=4326",
            dataset.Attribution + " " + dataset.LicenseUrl, dataset.LicenseUrl, now, .94)
        { SourceTitle = name + " - municipal heritage record", ExpiresUtc = now.AddDays(1) };
        var facts = new List<LocationFact>();
        var summary = status.Length > 0 ? $"The municipal heritage register records {name} with status: {status}."
            : $"{name} appears in the municipal heritage dataset.";
        // Listing and designation dates do not establish construction dates or a narrative.
        facts.Add(new(provider + ":" + id + ":register", "municipal_register_status", summary, source, .94, false, now));
        if (description.Length >= 40 && description.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length >= 6)
            facts.Add(new(provider + ":" + id + ":history", "municipal_historical_context",
                $"The municipal register describes {name}: {description}", source, .9, true, now));
        return new LocationPlace(provider + ":" + id, name, point, address, ["history", "architecture"], summary,
            facts, [source], new Dictionary<string, string> { [provider] = id }, null, null, null, null, .94, 0, [], [], null, null, now)
        { City = market.City, Region = "Ontario", CountryCode = "CA" };
    }

    private static LocationContextProviderResult Nearby(LocationContextProviderResult result, OntarioMarketOptions market, LocationContextQuery query) =>
        result with { Places = result.Places.Where(p => RouteMath.DistanceMeters(query.UserLocation, p.Coordinates)
            <= Math.Min(query.RadiusMeters, market.SearchRadiusMeters))
            .OrderBy(p => RouteMath.DistanceMeters(query.UserLocation, p.Coordinates)).Take(Math.Clamp(market.MaximumPlaces, 1, 100)).ToArray() };
    private static bool SameSite(LocationPlace a, LocationPlace b) =>
        a.Name.Equals(b.Name, StringComparison.OrdinalIgnoreCase) && a.Address == b.Address
        && RouteMath.DistanceMeters(a.Coordinates, b.Coordinates) < 15;
    private static bool IsWgs84(JsonElement root) => root.TryGetProperty("geometryType", out var type) && type.GetString() == "esriGeometryPoint"
        && root.TryGetProperty("spatialReference", out var sr) &&
        ((sr.TryGetProperty("wkid", out var wkid) && wkid.TryGetInt32(out var code) && code == 4326)
            || (sr.TryGetProperty("latestWkid", out var latest) && latest.TryGetInt32(out var latestCode) && latestCode == 4326));
    private static bool Https(string url) => Uri.TryCreate(url, UriKind.Absolute, out var uri)
        && uri.Scheme == "https" && uri.IsDefaultPort && uri.UserInfo.Length == 0;
    private static string Text(JsonElement fields, string name)
    {
        if (name.Length == 0 || !fields.TryGetProperty(name, out var value) || value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return "";
        if (value.ValueKind is not (JsonValueKind.String or JsonValueKind.Number)) return "";
        var text = WebUtility.HtmlDecode(Regex.Replace(value.ToString(), "<[^>]+>", " ")).Trim();
        text = Regex.Replace(text, @"\s+", " ");
        return text[..Math.Min(2000, text.Length)];
    }
}
