namespace Rover.Api.Contracts;

public sealed record WalkAdaptationResponse(
    string AdaptationId,
    string WalkSessionId,
    string Type,
    string Title,
    string Explanation,
    int EstimatedAddedMinutes,
    int EstimatedAddedDistanceMeters,
    int EstimatedNewTotalMinutes,
    IReadOnlyList<string> AffectedStops,
    IReadOnlyList<string> AddedStops,
    IReadOnlyList<string> RemovedStops,
    IReadOnlyList<string> ReorderedStops,
    WalkRouteResponse ProposedRoute,
    IReadOnlyList<WalkStopResponse> ProposedStops,
    int RouteRevision,
    int ProposedRouteRevision,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset ExpiresAtUtc,
    string Status);
