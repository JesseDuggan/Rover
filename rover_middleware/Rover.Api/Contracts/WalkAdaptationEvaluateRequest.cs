namespace Rover.Api.Contracts;

public sealed record WalkAdaptationEvaluateRequest(
    double? Latitude,
    double? Longitude,
    int? RouteRevision,
    string? RequestedType,
    int? AvailableMinutes,
    string? UserRequest,
    string? Interest,
    string? ProposedDiscoveryId,
    IReadOnlyCollection<string>? DismissedDiscoveryIds);
