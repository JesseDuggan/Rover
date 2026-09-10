namespace Rover.Api.Contracts;

public sealed record WalkSessionResponse(
    string WalkSessionId,
    string Status,
    LocationResponse StartingLocation,
    LocationResponse? LastKnownLocation,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset? StartedAtUtc,
    DateTimeOffset? CompletedAtUtc,
    DateTimeOffset? CancelledAtUtc,
    int AvailableMinutes,
    int EstimatedDurationMinutes,
    int EstimatedDistanceMeters,
    string RouteSummary,
    IReadOnlyCollection<string> Interests,
    string WalkingPace,
    IReadOnlyCollection<string> AccessibilityPreferences,
    int TimeRemainingMinutes,
    int VisitedStopCount,
    double WalkProgressPercentage,
    WalkStopResponse? NextStop,
    string? RecentNarrationStopId,
    WalkStopResponse? RecentNarration,
    WalkRouteResponse? Route,
    WalkRouteResponse? OriginalRoute,
    int RouteRevision,
    IReadOnlyList<WalkRouteRevisionResponse> RouteRevisions,
    double? DistanceToNextStopMeters,
    double RouteProgressPercentage,
    bool IsOffRoute,
    double DistanceFromRouteMeters,
    RouteQualityDiagnosticsResponse RouteQuality,
    StopLifecycleConsistencyResponse LifecycleConsistency,
    IReadOnlyList<WalkStopResponse> Stops);

public sealed record RouteQualityDiagnosticsResponse(
    int TotalRouteDistanceMeters,
    int EstimatedWalkingTimeMinutes,
    int EstimatedStopTimeMinutes,
    int EstimatedExperienceTimeMinutes,
    double AvailableTimeUtilization,
    int BacktrackingEstimateMeters,
    int RepeatedSegmentCount,
    int ReturnToStartEstimateMeters,
    IReadOnlyList<string> Warnings);

public sealed record StopLifecycleConsistencyResponse(
    bool IsConsistent,
    int StopCount,
    int RouteRevision,
    string? NextStopId,
    IReadOnlyList<string> Warnings);
