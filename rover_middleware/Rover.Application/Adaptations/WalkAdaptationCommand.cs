using Rover.Domain.Walks;

namespace Rover.Application.Adaptations;

public sealed record WalkAdaptationCommand(
    GeoLocation? CurrentLocation,
    int RouteRevision,
    WalkAdaptationType? RequestedType,
    int? AvailableMinutes,
    string? UserRequest,
    string? Interest,
    string? ProposedDiscoveryId,
    IReadOnlyCollection<string> DismissedDiscoveryIds);
