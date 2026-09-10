using System.Globalization;
using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Walks;

public sealed class GoogleRoutesWalkRouteProvider : IWalkRouteProvider
{
    private const string FieldMask =
        "routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline," +
        "routes.legs.steps.distanceMeters,routes.legs.steps.staticDuration," +
        "routes.legs.steps.navigationInstruction,routes.legs.steps.startLocation";

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly GoogleRoutesOptions _options;

    public GoogleRoutesWalkRouteProvider(
        IHttpClientFactory httpClientFactory,
        IOptions<GoogleRoutesOptions> options)
    {
        _httpClientFactory = httpClientFactory;
        _options = options.Value;
    }

    public string ProviderName => "GoogleRoutes";

    public async Task<WalkRoute> CreateRouteAsync(
        CreateWalkCommand command,
        IReadOnlyList<WalkStop> orderedStops,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.ApiKey))
        {
            throw new InvalidOperationException(
                "Google routing mode requires GOOGLE_ROUTES_API_KEY or GOOGLE_PLACES_API_KEY.");
        }

        if (orderedStops.Count == 0)
        {
            return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
        }

        try
        {
            var destination = orderedStops[^1].Location;
            var payload = new
            {
                origin = Waypoint(command.StartingLocation),
                destination = Waypoint(destination),
                intermediates = orderedStops
                    .Take(orderedStops.Count - 1)
                    .Select(stop => Waypoint(stop.Location))
                    .ToArray(),
                travelMode = "WALK",
                computeAlternativeRoutes = false,
                polylineQuality = "HIGH_QUALITY",
                polylineEncoding = "ENCODED_POLYLINE",
                languageCode = "en-CA",
                units = "METRIC"
            };

            using var request = new HttpRequestMessage(HttpMethod.Post, _options.Endpoint)
            {
                Content = new StringContent(
                    JsonSerializer.Serialize(payload),
                    Encoding.UTF8,
                    "application/json")
            };
            request.Headers.TryAddWithoutValidation("X-Goog-Api-Key", _options.ApiKey);
            request.Headers.TryAddWithoutValidation("X-Goog-FieldMask", FieldMask);

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(_options.Timeout);
            using var response = await _httpClientFactory
                .CreateClient("GoogleRoutes")
                .SendAsync(request, timeout.Token);

            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                throw new InvalidOperationException(
                    "Google Routes authorization failed. Enable Routes API and check the server-side key restrictions.");
            }

            if (!response.IsSuccessStatusCode)
            {
                return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
            }

            using var document = await JsonDocument.ParseAsync(
                await response.Content.ReadAsStreamAsync(timeout.Token),
                cancellationToken: timeout.Token);
            if (!document.RootElement.TryGetProperty("routes", out var routes)
                || routes.GetArrayLength() == 0)
            {
                return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
            }

            var route = routes[0];
            var encodedPolyline = route.GetProperty("polyline").GetProperty("encodedPolyline").GetString();
            var coordinates = DecodePolyline(encodedPolyline).ToArray();
            if (coordinates.Length < 2)
            {
                return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
            }

            var maneuvers = route.GetProperty("legs")
                .EnumerateArray()
                .SelectMany(leg => leg.GetProperty("steps").EnumerateArray())
                .Select((step, index) => ParseManeuver(step, index + 1))
                .ToArray();
            var bounds = new RouteBounds(
                new GeoLocation(
                    coordinates.Min(point => point.Latitude),
                    coordinates.Min(point => point.Longitude)),
                new GeoLocation(
                    coordinates.Max(point => point.Latitude),
                    coordinates.Max(point => point.Longitude)));

            return new WalkRoute(
                $"google-{Guid.NewGuid():n}",
                ProviderName,
                "google-routes-v2-walk",
                DateTimeOffset.UtcNow,
                coordinates,
                bounds,
                route.GetProperty("distanceMeters").GetInt32(),
                Math.Max(1, (int)Math.Ceiling(ParseDurationSeconds(route.GetProperty("duration")) / 60d)),
                maneuvers);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
        }
        catch (HttpRequestException)
        {
            return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
        }
        catch (JsonException)
        {
            return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
        }
        catch (KeyNotFoundException)
        {
            return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
        }
    }

    private static object Waypoint(GeoLocation location) => new
    {
        location = new
        {
            latLng = new
            {
                latitude = location.Latitude,
                longitude = location.Longitude
            }
        }
    };

    private static WalkRouteManeuver ParseManeuver(JsonElement step, int sequenceNumber)
    {
        var navigation = step.TryGetProperty("navigationInstruction", out var value)
            ? value
            : default;
        var instruction = navigation.ValueKind == JsonValueKind.Object
            && navigation.TryGetProperty("instructions", out var instructionValue)
            ? instructionValue.GetString() ?? "Continue walking."
            : "Continue walking.";
        var maneuverType = navigation.ValueKind == JsonValueKind.Object
            && navigation.TryGetProperty("maneuver", out var maneuverValue)
            ? maneuverValue.GetString() ?? "MANEUVER_UNSPECIFIED"
            : "MANEUVER_UNSPECIFIED";
        var location = ReadLocation(step);
        var seconds = step.TryGetProperty("staticDuration", out var duration)
            ? ParseDurationSeconds(duration)
            : 0;

        return new WalkRouteManeuver(
            sequenceNumber,
            instruction,
            step.TryGetProperty("distanceMeters", out var distance) ? distance.GetInt32() : 0,
            Math.Max(1, (int)Math.Ceiling(seconds / 60d)),
            maneuverType,
            location);
    }

    private static GeoLocation? ReadLocation(JsonElement step)
    {
        if (!step.TryGetProperty("startLocation", out var start)
            || !start.TryGetProperty("latLng", out var latLng)
            || !latLng.TryGetProperty("latitude", out var latitude)
            || !latLng.TryGetProperty("longitude", out var longitude))
        {
            return null;
        }

        return new GeoLocation(latitude.GetDouble(), longitude.GetDouble());
    }

    private static double ParseDurationSeconds(JsonElement duration)
    {
        var text = duration.GetString();
        return text is not null
            && text.EndsWith('s')
            && double.TryParse(text[..^1], NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds)
                ? seconds
                : 0;
    }

    private static IEnumerable<GeoLocation> DecodePolyline(string? encoded)
    {
        if (string.IsNullOrWhiteSpace(encoded))
        {
            yield break;
        }

        var index = 0;
        var latitude = 0;
        var longitude = 0;
        while (index < encoded.Length)
        {
            latitude += DecodeValue(encoded, ref index);
            longitude += DecodeValue(encoded, ref index);
            yield return new GeoLocation(latitude / 1e5, longitude / 1e5);
        }
    }

    private static int DecodeValue(string encoded, ref int index)
    {
        var result = 0;
        var shift = 0;
        int value;
        do
        {
            value = encoded[index++] - 63;
            result |= (value & 0x1f) << shift;
            shift += 5;
        }
        while (value >= 0x20 && index < encoded.Length);

        return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
    }

    private static Task<WalkRoute> CreateFallbackRouteAsync(
        CreateWalkCommand command,
        IReadOnlyList<WalkStop> orderedStops,
        CancellationToken cancellationToken)
        => new MockWalkRouteProvider().CreateRouteAsync(command, orderedStops, cancellationToken);
}
