using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Walks;

public sealed class MapboxWalkRouteProvider : IWalkRouteProvider
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly MapboxRoutingOptions _options;

    public MapboxWalkRouteProvider(IHttpClientFactory httpClientFactory, IOptions<MapboxRoutingOptions> options)
    {
        _httpClientFactory = httpClientFactory;
        _options = options.Value;
    }

    public string ProviderName => "Mapbox";

    public async Task<WalkRoute> CreateRouteAsync(CreateWalkCommand command, IReadOnlyList<WalkStop> orderedStops, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(_options.AccessToken))
        {
            throw new InvalidOperationException("Mapbox routing mode requires MAPBOX_DIRECTIONS_TOKEN or user secret Rover:Routing:Mapbox:AccessToken.");
        }

        try
        {
            var waypoints = new[] { command.StartingLocation }.Concat(orderedStops.Select(stop => stop.Location)).ToArray();
            var waypointText = string.Join(";", waypoints.Select(point => $"{point.Longitude.ToString(System.Globalization.CultureInfo.InvariantCulture)},{point.Latitude.ToString(System.Globalization.CultureInfo.InvariantCulture)}"));
            var url = $"https://api.mapbox.com/directions/v5/mapbox/walking/{waypointText}?geometries=geojson&overview=full&steps=true&access_token={Uri.EscapeDataString(_options.AccessToken)}";
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(_options.Timeout);

            using var response = await _httpClientFactory.CreateClient("MapboxDirections").GetAsync(url, timeout.Token);
            if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden)
            {
                throw new InvalidOperationException("Mapbox routing authorization failed. Check the configured server-side token.");
            }

            if (!response.IsSuccessStatusCode)
            {
                return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
            }

            using var document = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(timeout.Token), cancellationToken: timeout.Token);
            var route = document.RootElement.GetProperty("routes").EnumerateArray().FirstOrDefault();
            if (route.ValueKind == JsonValueKind.Undefined)
            {
                return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
            }

            var coordinates = route.GetProperty("geometry").GetProperty("coordinates")
                .EnumerateArray()
                .Select(item => new GeoLocation(item[1].GetDouble(), item[0].GetDouble()))
                .ToArray();

            if (coordinates.Length < 2)
            {
                return await CreateFallbackRouteAsync(command, orderedStops, cancellationToken);
            }

            var bounds = new RouteBounds(
                new GeoLocation(coordinates.Min(point => point.Latitude), coordinates.Min(point => point.Longitude)),
                new GeoLocation(coordinates.Max(point => point.Latitude), coordinates.Max(point => point.Longitude)));
            var maneuvers = route.GetProperty("legs")
                .EnumerateArray()
                .SelectMany(leg => leg.GetProperty("steps").EnumerateArray())
                .Select((step, index) => new WalkRouteManeuver(
                    index + 1,
                    ReadInstruction(step),
                    (int)Math.Round(step.GetProperty("distance").GetDouble()),
                    Math.Max(1, (int)Math.Ceiling(step.GetProperty("duration").GetDouble() / 60))))
                .ToArray();

            return new WalkRoute(
                $"mapbox-{Guid.NewGuid():n}",
                ProviderName,
                "mapbox-walking-geojson-v1",
                DateTimeOffset.UtcNow,
                coordinates,
                bounds,
                (int)Math.Round(route.GetProperty("distance").GetDouble()),
                (int)Math.Ceiling(route.GetProperty("duration").GetDouble() / 60),
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

    private static Task<WalkRoute> CreateFallbackRouteAsync(
        CreateWalkCommand command,
        IReadOnlyList<WalkStop> orderedStops,
        CancellationToken cancellationToken)
        => new MockWalkRouteProvider().CreateRouteAsync(command, orderedStops, cancellationToken);

    private static string ReadInstruction(JsonElement step)
    {
        if (step.TryGetProperty("maneuver", out var maneuver)
            && maneuver.TryGetProperty("instruction", out var instruction)
            && instruction.ValueKind == JsonValueKind.String)
        {
            return instruction.GetString() ?? "Continue walking.";
        }

        return "Continue walking.";
    }
}
