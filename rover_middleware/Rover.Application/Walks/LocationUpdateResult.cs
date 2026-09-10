using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public sealed record LocationUpdateResult(
    string WalkSessionId,
    WalkSessionStatus Status,
    bool Accepted,
    WalkStop? NextStop,
    double? DistanceToNextStopMeters,
    double RouteProgressPercentage,
    int EstimatedMinutesRemaining,
    bool IsOffRoute,
    double DistanceFromRouteMeters,
    bool ArrivalCandidate,
    int ArrivalCandidateReadingCount,
    string? ArrivalCandidateStopId,
    WalkStop? ConfirmedArrival,
    DateTimeOffset ServerTimestampUtc);
