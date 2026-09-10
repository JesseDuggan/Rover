namespace Rover.Api.Contracts;

public sealed record WalkRouteResponse(
    string RouteId,
    string Provider,
    string Version,
    DateTimeOffset GeneratedAtUtc,
    IReadOnlyList<RouteCoordinateResponse> Coordinates,
    object GeoJson,
    RouteBoundsResponse Bounds,
    int DistanceMeters,
    int DurationMinutes,
    IReadOnlyList<WalkRouteManeuverResponse> Maneuvers);

public sealed record WalkRouteManeuverResponse(
    int SequenceNumber,
    string Instruction,
    int DistanceMeters,
    int DurationMinutes,
    string ManeuverType,
    RouteCoordinateResponse? Location);
