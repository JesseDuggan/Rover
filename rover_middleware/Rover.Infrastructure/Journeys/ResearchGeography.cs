using System.Globalization;
using System.Text.Json;
using Rover.Application.Journeys;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Journeys;

public sealed class ResearchGeographyOptions { public string? ApiKey { get; set; } }

// One bounded reverse lookup per live area-research request, never per GPS update.
public sealed class ResearchGeography(HttpClient client, ResearchGeographyOptions options)
{
    public async Task<ResearchAreaContext?> ResolveAsync(GeoLocation point, string language, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(options.ApiKey)) {
            StoryInspection.Record("Geographic context", "Unavailable", "Reverse geocoding key is not configured; names must be established from cited geographic evidence.");
            return null;
        }
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(TimeSpan.FromSeconds(6));
        try {
            var coords = string.Create(CultureInfo.InvariantCulture, $"{point.Latitude},{point.Longitude}");
            using var request = new HttpRequestMessage(HttpMethod.Get, "https://maps.googleapis.com/maps/api/geocode/json?latlng=" + coords + "&language=" + Uri.EscapeDataString(language) + "&key=" + Uri.EscapeDataString(options.ApiKey));
            request.Options.Set(new HttpRequestOptionsKey<string>("Walkabout.Usage.Purpose"), "Resolve research neighbourhood");
            using var response = await client.SendAsync(request, budget.Token);
            if (!response.IsSuccessStatusCode) { StoryInspection.Record("Geographic context", "Unavailable", "Reverse geocoding HTTP " + (int)response.StatusCode); return null; }
            using var doc = JsonDocument.Parse(await response.Content.ReadAsStringAsync(budget.Token));
            var result = Parse(doc.RootElement, point);
            StoryInspection.Record("Geographic context", result is null ? "Unresolved" : "Resolved", result is null
                ? "No nearby address or containing administrative area was resolved. Do not infer the neighbourhood from a famous district."
                : $"Google reverse geocoding: neighbourhood {result.Neighbourhood ?? "not supplied"}; district {result.District ?? "not supplied"}; locality {result.City ?? "not supplied"}; region {result.Region ?? "not supplied"}; country {result.Country ?? "not supplied"}. Geographic context only, not evidence for historical claims.");
            return result;
        } catch (OperationCanceledException) when (!token.IsCancellationRequested) {
            StoryInspection.Record("Geographic context", "Timed out", "Bounded reverse lookup timed out; no area name guessed."); return null;
        } catch (Exception e) when (e is HttpRequestException or JsonException or InvalidOperationException or FormatException or KeyNotFoundException) {
            StoryInspection.Record("Geographic context", "Unavailable", "Reverse lookup failed validation; no area name guessed."); return null;
        }
    }

    public static ResearchAreaContext? Parse(JsonElement root, GeoLocation point)
    {
        if (!root.TryGetProperty("status", out var status) || status.GetString() != "OK" || !root.TryGetProperty("results", out var results) || results.ValueKind != JsonValueKind.Array) return null;
        // Take all components from one result, not a blend of neighbouring districts.
        ResearchAreaContext? fallback = null;
        foreach (var result in results.EnumerateArray()) {
            if (!result.TryGetProperty("geometry", out var geometry) || !geometry.TryGetProperty("location", out var location)) continue;
            GeoLocation Read(JsonElement e) => new(e.GetProperty("lat").GetDouble(), e.GetProperty("lng").GetDouble());
            var subject = Read(location);
            if (!double.IsFinite(subject.Latitude) || !double.IsFinite(subject.Longitude)) continue;
            var nearby = RouteMath.DistanceMeters(point, subject) <= 150;
            var contains = false;
            if (geometry.TryGetProperty("bounds", out var bounds)) {
                var sw = Read(bounds.GetProperty("southwest")); var ne = Read(bounds.GetProperty("northeast"));
                contains = point.Latitude >= sw.Latitude && point.Latitude <= ne.Latitude &&
                    (sw.Longitude <= ne.Longitude ? point.Longitude >= sw.Longitude && point.Longitude <= ne.Longitude : point.Longitude >= sw.Longitude || point.Longitude <= ne.Longitude);
            }
            if (!nearby && !contains) continue;
            if (!result.TryGetProperty("address_components", out var components)) continue;
            string? Name(params string[] types) {
                foreach (var type in types) foreach (var c in components.EnumerateArray())
                    if (c.GetProperty("types").EnumerateArray().Any(t => t.GetString() == type) && c.TryGetProperty("long_name", out var name) && name.GetString() is { Length: > 0 and <= 160 } value && !value.Any(char.IsControl)) return value;
                return null;
            }
            var city = Name("locality", "postal_town");
            var neighbourhood = Name("neighborhood");
            var district = Name("sublocality_level_5", "sublocality_level_4", "sublocality_level_3", "sublocality_level_2", "sublocality_level_1", "sublocality", "administrative_area_level_3", "administrative_area_level_2");
            if (city is null && neighbourhood is null && district is null) continue;
            var context = new ResearchAreaContext(neighbourhood, Name("route"), city, Name("administrative_area_level_1"), Name("country"), "Google Geocoding", district);
            if (neighbourhood is not null) return context;
            fallback ??= context;
        }
        return fallback;
    }
}
