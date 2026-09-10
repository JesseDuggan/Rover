namespace Rover.Domain.Profiles;

public sealed class GuestProfile
{
    public GuestProfile(Guid profileId, string installationId, DateTimeOffset createdAtUtc, DateTimeOffset updatedAtUtc, UserPreferences preferences)
    {
        ProfileId = profileId;
        InstallationId = installationId;
        CreatedAtUtc = createdAtUtc;
        UpdatedAtUtc = updatedAtUtc;
        Preferences = preferences;
    }

    public Guid ProfileId { get; }
    public string InstallationId { get; }
    public DateTimeOffset CreatedAtUtc { get; }
    public DateTimeOffset UpdatedAtUtc { get; private set; }
    public UserPreferences Preferences { get; private set; }
    public List<SavedDiscovery> SavedDiscoveries { get; } = new();
    public List<PreferenceSignal> PreferenceSignals { get; } = new();
    public List<LearnedPreference> LearnedPreferences { get; } = new();
    public List<StoryInteraction> StoryInteractions { get; } = new();
    public uint Version { get; private set; }

    public void UpdatePreferences(UserPreferences preferences, DateTimeOffset updatedAtUtc)
    {
        Preferences = preferences;
        UpdatedAtUtc = updatedAtUtc;
        Version++;
    }

    public void SaveDiscovery(SavedDiscovery discovery)
    {
        if (SavedDiscoveries.Any(item => item.DiscoveryId.Equals(discovery.DiscoveryId, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        SavedDiscoveries.Add(discovery);
        Version++;
    }

    public void RemoveDiscovery(string discoveryId)
    {
        SavedDiscoveries.RemoveAll(item => item.DiscoveryId.Equals(discoveryId, StringComparison.OrdinalIgnoreCase));
        Version++;
    }

    public void RecordSignal(PreferenceSignal signal)
    {
        if (!Preferences.ImproveRecommendations)
        {
            return;
        }

        PreferenceSignals.Add(signal);
        var learned = LearnedPreferences.FirstOrDefault(item => item.Topic.Equals(signal.Topic, StringComparison.OrdinalIgnoreCase));
        if (learned is null)
        {
            LearnedPreferences.Add(new LearnedPreference(signal.Topic, signal.Weight, signal.Reason, signal.CreatedAtUtc));
            Version++;
            return;
        }

        learned.Apply(signal);
        Version++;
    }

    public void RemoveLearnedPreference(string topic)
    {
        LearnedPreferences.RemoveAll(item => item.Topic.Equals(topic, StringComparison.OrdinalIgnoreCase));
        PreferenceSignals.RemoveAll(item => item.Topic.Equals(topic, StringComparison.OrdinalIgnoreCase));
        Version++;
    }

    public void ResetLearning()
    {
        LearnedPreferences.Clear();
        PreferenceSignals.Clear();
        StoryInteractions.Clear();
        Version++;
    }

    public bool RecordStoryInteraction(StoryInteraction interaction, int maximumEvents, DateTimeOffset oldestAllowedUtc)
    {
        if (!Preferences.ImproveRecommendations
            || StoryInteractions.Any(item => item.EventId.Equals(interaction.EventId, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        StoryInteractions.RemoveAll(item => item.OccurredAtUtc < oldestAllowedUtc);
        StoryInteractions.Add(interaction);
        var overflow = StoryInteractions.Count - Math.Max(1, maximumEvents);
        if (overflow > 0)
        {
            StoryInteractions.RemoveRange(0, overflow);
        }
        Version++;
        return true;
    }
}

public sealed record UserPreferences(
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

    public static UserPreferences Default => new(
        Array.Empty<string>(),
        "Standard",
        Array.Empty<string>(),
        "miles",
        true,
        true,
        0.48,
        "Balanced",
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        "WalkRestorationOnly");
}

public sealed record SavedDiscovery(Guid SavedDiscoveryId, string DiscoveryId, string Name, string Category, DateTimeOffset SavedAtUtc, string Source);
public sealed record PreferenceSignal(Guid PreferenceSignalId, string Topic, int Weight, string Reason, DateTimeOffset CreatedAtUtc);

public enum StoryInteractionKind
{
    Offered,
    Started,
    Completed,
    Skipped,
    Interrupted,
    Replayed,
    TellMore,
    Dismissed
}

public sealed record StoryInteraction(
    string EventId,
    string StoryId,
    string Category,
    StoryInteractionKind Kind,
    DateTimeOffset OccurredAtUtc);

public sealed class LearnedPreference
{
    public LearnedPreference(string topic, int score, string reason, DateTimeOffset updatedAtUtc)
    {
        Topic = topic;
        Score = Math.Clamp(score, -10, 10);
        Reason = reason;
        UpdatedAtUtc = updatedAtUtc;
    }

    public string Topic { get; }
    public int Score { get; private set; }
    public string Reason { get; private set; }
    public DateTimeOffset UpdatedAtUtc { get; private set; }

    public void Apply(PreferenceSignal signal)
    {
        Score = Math.Clamp(Score + Math.Clamp(signal.Weight, -3, 3), -10, 10);
        Reason = signal.Reason;
        UpdatedAtUtc = signal.CreatedAtUtc;
    }
}
