namespace Rover.Api.Contracts;

public sealed record JourneyNarrationEvaluateRequest(
    double Latitude,
    double Longitude,
    double? GpsAccuracyMeters,
    double? HeadingDegrees,
    double? SpeedMetersPerSecond,
    IReadOnlyList<string>? AlreadyNarratedFactIds,
    DateTimeOffset? RequestedAtUtc)
{
    public int? SecondsUntilNextManeuver { get; init; }
    public int? StoryDurationSeconds { get; init; }
    public string? StoryDensity { get; init; }
    public IReadOnlyList<string>? PreferredStoryCategories { get; init; }
    public IReadOnlyList<string>? ExcludedStoryCategories { get; init; }
    public string? RouteState { get; init; }
    public bool? UserAttentionAvailable { get; init; }
    public bool? RecentDirectInteraction { get; init; }
    public bool? ConnectivityAvailable { get; init; }
    public bool? AudioAlreadyQueued { get; init; }
    public bool? BatterySaverEnabled { get; init; }
    public string? ThermalState { get; init; }
    public string? InterruptedStoryId { get; init; }
    public string? InterruptedStoryRouteId { get; init; }
    public DateTimeOffset? InterruptedStoryExpiresUtc { get; init; }
    public bool? InterruptedStoryStillRelevant { get; init; }
    public Guid? ProfileId { get; init; }
}

public sealed record JourneyNarrationDecisionResponse(
    bool ShouldNarrate,
    string Kind,
    string Priority,
    string? NarrationText,
    string? PlaceId,
    IReadOnlyList<string> FactIdsUsed,
    IReadOnlyList<LocationSourceResponse> SourceReferences,
    int CooldownSeconds,
    IReadOnlyList<string> Warnings)
{
    public bool SchedulerApplied { get; init; }
    public string ScheduleAction { get; init; } = "Narrate";
    public string? ScheduleReason { get; init; }
    public string? StoryId { get; init; }
    public DateTimeOffset? StoryExpiresUtc { get; init; }
    public int? EstimatedDurationSeconds { get; init; }
    public double? RankingScore { get; init; }
    public IReadOnlyList<string> RankingReasons { get; init; } = Array.Empty<string>();
    public bool AudioCacheEligible { get; init; }
    public string RetentionClass { get; init; } = "restricted";
}
