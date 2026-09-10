namespace Rover.Api.Contracts;

public sealed record LocationUpdateResponse(
    string WalkSessionId,
    string Status,
    bool Accepted,
    WalkStopResponse? NextStop,
    double? DistanceToNextStopMeters,
    double RouteProgressPercentage,
    int EstimatedMinutesRemaining,
    bool IsOffRoute,
    double DistanceFromRouteMeters,
    bool ArrivalCandidate,
    int ArrivalCandidateReadingCount,
    string? ArrivalCandidateStopId,
    WalkStopResponse? ConfirmedArrival,
    DateTimeOffset ServerTimestampUtc);
