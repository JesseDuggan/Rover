using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public sealed record LocationUpdateCommand(
    GeoLocation Location,
    double? AccuracyMeters,
    double? HeadingDegrees,
    double? SpeedMetersPerSecond,
    DateTimeOffset RecordedAtUtc);
