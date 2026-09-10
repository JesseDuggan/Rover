namespace Rover.Domain.Walks;

public sealed class WalkRoute
{
    public WalkRoute(
        string routeId,
        string provider,
        string version,
        DateTimeOffset generatedAtUtc,
        IReadOnlyList<GeoLocation> coordinates,
        RouteBounds bounds,
        int distanceMeters,
        int durationMinutes,
        IReadOnlyList<WalkRouteManeuver>? maneuvers = null)
    {
        if (coordinates.Count < 2)
        {
            throw new ArgumentException("A route requires at least two coordinates.", nameof(coordinates));
        }

        RouteId = routeId;
        Provider = provider;
        Version = version;
        GeneratedAtUtc = generatedAtUtc;
        Coordinates = coordinates;
        Bounds = bounds;
        DistanceMeters = distanceMeters;
        DurationMinutes = durationMinutes;
        Maneuvers = maneuvers ?? Array.Empty<WalkRouteManeuver>();
    }

    public string RouteId { get; }
    public string Provider { get; }
    public string Version { get; }
    public DateTimeOffset GeneratedAtUtc { get; }
    public IReadOnlyList<GeoLocation> Coordinates { get; }
    public RouteBounds Bounds { get; }
    public int DistanceMeters { get; }
    public int DurationMinutes { get; }
    public IReadOnlyList<WalkRouteManeuver> Maneuvers { get; }
}
