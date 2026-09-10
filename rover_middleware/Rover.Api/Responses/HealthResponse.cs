namespace Rover.Api.Responses;

public sealed record HealthResponse(
    string Service,
    string Status,
    DateTimeOffset CheckedAtUtc);
