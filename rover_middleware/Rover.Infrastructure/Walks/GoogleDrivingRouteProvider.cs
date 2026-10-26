using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Rover.Application.Drives;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Walks;

public sealed class GoogleDrivingRouteProvider(IHttpClientFactory clients, IOptions<GoogleRoutesOptions> options)
    : IDrivingRouteProvider
{
    public async Task<DrivingRoute> RouteAsync(GeoLocation origin, IReadOnlyList<GeoLocation> visits, CancellationToken ct, DrivePreferences? preferences = null)
    {
        if (string.IsNullOrWhiteSpace(options.Value.ApiKey))
            throw new DrivingUnavailableException("Driving routes are not configured yet.");
        if (!ScenicDriveService.ValidLocation(origin) || visits.Count is < 1 or > 8 ||
            visits.Any(p => !ScenicDriveService.ValidLocation(p)))
            throw new ArgumentException("Invalid driving waypoints.");
        object Waypoint(GeoLocation p) => new { location = new { latLng = new { latitude = p.Latitude, longitude = p.Longitude } } };
        using var request = new HttpRequestMessage(HttpMethod.Post, options.Value.Endpoint)
        {
            Content = JsonContent.Create(new {
                origin = Waypoint(origin), destination = Waypoint(visits[^1]),
                intermediates = visits.SkipLast(1).Select(Waypoint).ToArray(),
                travelMode = "DRIVE", routingPreference = "TRAFFIC_AWARE",
                routeModifiers = new { avoidHighways = preferences?.PreferLocalRoads ?? false, avoidTolls = preferences?.AvoidTolls ?? false },
                computeAlternativeRoutes = false, polylineQuality = "HIGH_QUALITY",
                polylineEncoding = "GEO_JSON_LINESTRING", languageCode = "en", units = "METRIC"
            })
        };
        request.Headers.Add("X-Goog-Api-Key", options.Value.ApiKey);
        request.Headers.Add("X-Goog-FieldMask", "routes.duration,routes.distanceMeters,routes.polyline.geoJsonLinestring");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(options.Value.Timeout);
        try
        {
            using var response = await clients.CreateClient("GoogleRoutes").SendAsync(request, timeout.Token);
            if (!response.IsSuccessStatusCode) throw new DrivingUnavailableException("Driving directions are unavailable. Please try again.");
            using var json = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(timeout.Token), cancellationToken: timeout.Token);
            var items = json.RootElement.GetProperty("routes");
            if (items.GetArrayLength() == 0) throw new DrivingUnavailableException("No driving route was found to that destination.");
            var route = items[0];
            var duration = route.GetProperty("duration").GetString() ?? "";
            if (!duration.EndsWith('s') || !double.TryParse(duration[..^1], NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds) ||
                !double.IsFinite(seconds) || seconds <= 0 || seconds > 604800)
                throw new DrivingUnavailableException("Driving time could not be verified.");
            var distance = route.GetProperty("distanceMeters").GetInt32();
            var geometry = route.GetProperty("polyline").GetProperty("geoJsonLinestring").GetProperty("coordinates")
                .EnumerateArray().Select(p => new GeoLocation(p[1].GetDouble(), p[0].GetDouble())).ToArray();
            if (distance <= 0 || geometry.Length < 2 || geometry.Any(p => !ScenicDriveService.ValidLocation(p)))
                throw new DrivingUnavailableException("Driving route geometry could not be verified.");
            return new((int)Math.Ceiling(seconds / 60), distance, geometry);
        }
        catch (Exception e) when (e is HttpRequestException or JsonException or KeyNotFoundException or InvalidOperationException or FormatException ||
            e is OperationCanceledException && !ct.IsCancellationRequested)
        {
            throw new DrivingUnavailableException("Driving directions are temporarily unavailable. Please try again.");
        }
    }
}
