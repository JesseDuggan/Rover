namespace Rover.Api.Responses;

public sealed record HealthResponse(
    string Status,
    string Version);
