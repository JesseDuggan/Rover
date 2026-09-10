namespace Rover.Api.Contracts;

public sealed record GenerateAdaptiveRouteStoryPackRequest(
    Guid? ProfileId,
    string? Audience,
    string? Language,
    bool? ForceRefresh);

public sealed record NextAdaptiveRouteStoryRequest(
    double? RouteProgressMeters,
    int? SecondsUntilNextManeuver,
    string? PreferredLength,
    IReadOnlyList<string>? ExcludedStoryIds);

public sealed record AdaptiveRouteStoryQuestionRequest(
    string? Question,
    double? RouteProgressMeters,
    int? SecondsUntilNextManeuver);

public sealed record AdaptiveStoryPlaybackEventRequest(
    string? StoryId,
    string? Kind,
    DateTimeOffset? OccurredUtc,
    int? PositionSeconds);
