namespace Rover.Domain.Walks;

public sealed record WalkRouteManeuver(
    int SequenceNumber,
    string Instruction,
    int DistanceMeters,
    int DurationMinutes,
    string ManeuverType = "MANEUVER_UNSPECIFIED",
    GeoLocation? Location = null);
