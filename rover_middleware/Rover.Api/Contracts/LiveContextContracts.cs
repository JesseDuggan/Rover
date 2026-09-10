namespace Rover.Api.Contracts;

public sealed record LiveContextRequest(
    double Latitude,
    double Longitude,
    string? City,
    string? Region,
    string? Country,
    string? TimeZone,
    DateTimeOffset? JourneyStartsUtc,
    DateTimeOffset? JourneyEndsUtc,
    IReadOnlyList<string>? Interests,
    bool UserRequested);
