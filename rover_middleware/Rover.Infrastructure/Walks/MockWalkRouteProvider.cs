using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Walks;

public sealed class MockWalkRouteProvider : IWalkRouteProvider
{
    public string ProviderName => "Mock";

    public Task<WalkRoute> CreateRouteAsync(CreateWalkCommand command, IReadOnlyList<WalkStop> orderedStops, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var coordinates = new List<GeoLocation> { command.StartingLocation };
        coordinates.AddRange(orderedStops.Select(stop => stop.Location));
        var bounds = CreateBounds(coordinates);
        var distanceMeters = (int)Math.Round(SumDistance(coordinates));
        var maneuvers = orderedStops
            .Select((stop, index) => new WalkRouteManeuver(
                index + 1,
                $"Walk to stop {index + 1}: {stop.Name}.",
                index == 0 ? 0 : stop.DistanceFromPreviousStopMeters,
                Math.Max(1, stop.DistanceFromPreviousStopMeters / 80)))
            .ToArray();

        var walkingDurationMinutes = Math.Max(1, (int)Math.Ceiling(distanceMeters / 80d));

        return Task.FromResult(new WalkRoute(
            "mock-union-square-v1",
            ProviderName,
            "union-square-v1",
            DateTimeOffset.UtcNow,
            coordinates,
            bounds,
            distanceMeters,
            walkingDurationMinutes,
            maneuvers));
    }

    private static RouteBounds CreateBounds(IReadOnlyList<GeoLocation> coordinates)
    {
        return new RouteBounds(
            new GeoLocation(coordinates.Min(point => point.Latitude), coordinates.Min(point => point.Longitude)),
            new GeoLocation(coordinates.Max(point => point.Latitude), coordinates.Max(point => point.Longitude)));
    }

    private static double SumDistance(IReadOnlyList<GeoLocation> coordinates)
    {
        var sum = 0d;
        for (var i = 1; i < coordinates.Count; i++)
        {
            sum += RouteMath.DistanceMeters(coordinates[i - 1], coordinates[i]);
        }

        return sum;
    }
}
