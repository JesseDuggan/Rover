namespace Rover.Domain.Walks;

public sealed record WalkTrackingState(
    double? DistanceToNextStopMeters,
    double RouteProgressPercentage,
    int EstimatedMinutesRemaining,
    bool IsOffRoute,
    double DistanceFromRouteMeters,
    string? ArrivalCandidateStopId,
    DateTimeOffset? LastLocationRecordedAtUtc);
