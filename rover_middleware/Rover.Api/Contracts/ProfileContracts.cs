namespace Rover.Api.Contracts;

public sealed record CreateGuestProfileRequest(string? InstallationId);

public sealed record UpdateUserPreferencesRequest(
    IReadOnlyList<string>? Interests,
    string? WalkingPace,
    IReadOnlyList<string>? AccessibilityNeeds,
    string? DistanceUnits,
    bool? DirectionVoiceEnabled,
    bool? NarrationEnabled,
    double? SpeechRate,
    string? PreferredNarrationLength,
    bool? PremiumVoiceEnabled,
    bool? AskRoverVoiceEnabled,
    bool? AutoPlayNarrationOnArrival,
    bool? ResumeNarrationAfterNavigation,
    bool? DeviceVoiceFallbackEnabled,
    bool? SaveWalkHistory,
    bool? ImproveRecommendations,
    string? LocationRetention)
{
    public string? StoryDensity { get; init; }
    public IReadOnlyList<string>? ExcludedStoryCategories { get; init; }
}

public sealed record SaveDiscoveryRequest(string? DiscoveryId, string? Name, string? Category, string? Source);
public sealed record PreferenceSignalRequest(string? Topic, int? Weight, string? Reason);
public sealed record StoryInteractionRequest(string? EventId, string? StoryId, string? Category, string? Kind, DateTimeOffset? OccurredAtUtc);

public sealed record ProfileResponse(
    Guid ProfileId,
    string InstallationId,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc,
    UserPreferencesResponse Preferences,
    IReadOnlyList<SavedDiscoveryResponse> SavedDiscoveries,
    IReadOnlyList<LearnedPreferenceResponse> LearnedPreferences,
    uint Version)
{
    public int StoryInteractionCount { get; init; }
}

public sealed record UserPreferencesResponse(
    IReadOnlyList<string> Interests,
    string WalkingPace,
    IReadOnlyList<string> AccessibilityNeeds,
    string DistanceUnits,
    bool DirectionVoiceEnabled,
    bool NarrationEnabled,
    double SpeechRate,
    string PreferredNarrationLength,
    bool PremiumVoiceEnabled,
    bool AskRoverVoiceEnabled,
    bool AutoPlayNarrationOnArrival,
    bool ResumeNarrationAfterNavigation,
    bool DeviceVoiceFallbackEnabled,
    bool SaveWalkHistory,
    bool ImproveRecommendations,
    string LocationRetention)
{
    public string StoryDensity { get; init; } = "Highlights";
    public IReadOnlyList<string> ExcludedStoryCategories { get; init; } = Array.Empty<string>();
}

public sealed record SavedDiscoveryResponse(Guid SavedDiscoveryId, string DiscoveryId, string Name, string Category, DateTimeOffset SavedAtUtc, string Source);
public sealed record LearnedPreferenceResponse(string Topic, int Score, string Reason, DateTimeOffset UpdatedAtUtc);
