namespace Rover.Api.Contracts;

public sealed record LocationUpdateRequest(
    double? Latitude,
    double? Longitude,
    double? AccuracyMeters,
    double? HeadingDegrees,
    double? SpeedMetersPerSecond,
    DateTimeOffset? RecordedAtUtc);
