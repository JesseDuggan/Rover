using Rover.Domain.Profiles;

namespace Rover.Application.Profiles;

public sealed record CreateGuestProfileCommand(string InstallationId);

public sealed record UpdateUserPreferencesCommand(
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

    public UserPreferences ApplyTo(UserPreferences current)
    {
        var updated = new UserPreferences(
            Interests ?? current.Interests,
            string.IsNullOrWhiteSpace(WalkingPace) ? current.WalkingPace : WalkingPace.Trim(),
            AccessibilityNeeds ?? current.AccessibilityNeeds,
            string.IsNullOrWhiteSpace(DistanceUnits) ? current.DistanceUnits : DistanceUnits.Trim(),
            DirectionVoiceEnabled ?? current.DirectionVoiceEnabled,
            NarrationEnabled ?? current.NarrationEnabled,
            Math.Clamp(SpeechRate ?? current.SpeechRate, 0.3, 0.65),
            string.IsNullOrWhiteSpace(PreferredNarrationLength) ? current.PreferredNarrationLength : PreferredNarrationLength.Trim(),
            PremiumVoiceEnabled ?? current.PremiumVoiceEnabled,
            AskRoverVoiceEnabled ?? current.AskRoverVoiceEnabled,
            AutoPlayNarrationOnArrival ?? current.AutoPlayNarrationOnArrival,
            ResumeNarrationAfterNavigation ?? current.ResumeNarrationAfterNavigation,
            DeviceVoiceFallbackEnabled ?? current.DeviceVoiceFallbackEnabled,
            SaveWalkHistory ?? current.SaveWalkHistory,
            ImproveRecommendations ?? current.ImproveRecommendations,
            string.IsNullOrWhiteSpace(LocationRetention) ? current.LocationRetention : LocationRetention.Trim());
        return updated with
        {
            StoryDensity = NormalizeStoryDensity(StoryDensity, current.StoryDensity),
            ExcludedStoryCategories = ExcludedStoryCategories is null
                ? current.ExcludedStoryCategories
                : ExcludedStoryCategories
                    .Select(value => value.Trim())
                    .Where(value => value.Length > 0)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
                    .ToArray()
        };
    }

    private static string NormalizeStoryDensity(string? requested, string current)
    {
        if (string.IsNullOrWhiteSpace(requested)) return current;
        return requested.Trim().ToLowerInvariant() switch
        {
            "quiet" => "Quiet",
            "highlights" => "Highlights",
            "story-rich" or "storyrich" or "rich" => "Story-Rich",
            _ => current
        };
    }
}

public sealed record SaveDiscoveryCommand(string DiscoveryId, string Name, string Category, string Source);
public sealed record PreferenceSignalCommand(string Topic, int Weight, string Reason);
public sealed record StoryInteractionCommand(string EventId, string StoryId, string Category, string Kind, DateTimeOffset? OccurredAtUtc);
