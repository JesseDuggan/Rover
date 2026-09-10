using Rover.Domain.Profiles;

namespace Rover.Application.Profiles;

using Rover.Application.Journeys;

public sealed class ProfileService : IProfileService
{
    private readonly IProfileRepository _profiles;
    private readonly TimeProvider _timeProvider;
    private readonly Phase15Options _phase15Options;

    public ProfileService(IProfileRepository profiles, TimeProvider timeProvider, Phase15Options? phase15Options = null)
    {
        _profiles = profiles;
        _timeProvider = timeProvider;
        _phase15Options = phase15Options ?? new Phase15Options();
    }

    public async Task<GuestProfile> CreateOrGetGuestAsync(CreateGuestProfileCommand command, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(command.InstallationId))
        {
            throw new ArgumentException("Installation identifier is required.", nameof(command));
        }

        var installationId = command.InstallationId.Trim();
        var existing = await _profiles.GetByInstallationIdAsync(installationId, cancellationToken);
        if (existing is not null)
        {
            return existing;
        }

        var now = _timeProvider.GetUtcNow();
        var profile = new GuestProfile(Guid.NewGuid(), installationId, now, now, UserPreferences.Default);
        await _profiles.AddAsync(profile, cancellationToken);
        return profile;
    }

    public Task<GuestProfile?> GetAsync(Guid profileId, CancellationToken cancellationToken) => _profiles.GetByIdAsync(profileId, cancellationToken);

    public async Task<GuestProfile> UpdatePreferencesAsync(Guid profileId, UpdateUserPreferencesCommand command, CancellationToken cancellationToken)
    {
        var profile = await GetRequiredAsync(profileId, cancellationToken);
        var previousLearning = profile.Preferences.ImproveRecommendations;
        profile.UpdatePreferences(command.ApplyTo(profile.Preferences), _timeProvider.GetUtcNow());
        if (previousLearning && !profile.Preferences.ImproveRecommendations)
        {
            profile.ResetLearning();
        }
        await _profiles.UpdateAsync(profile, cancellationToken);
        return profile;
    }

    public async Task<GuestProfile> SaveDiscoveryAsync(Guid profileId, SaveDiscoveryCommand command, CancellationToken cancellationToken)
    {
        var profile = await GetRequiredAsync(profileId, cancellationToken);
        var now = _timeProvider.GetUtcNow();
        profile.SaveDiscovery(new SavedDiscovery(Guid.NewGuid(), command.DiscoveryId.Trim(), command.Name.Trim(), command.Category.Trim(), now, command.Source.Trim()));
        profile.RecordSignal(new PreferenceSignal(Guid.NewGuid(), command.Category.Trim(), 1, $"Saved discovery: {command.Name.Trim()}", now));
        await _profiles.UpdateAsync(profile, cancellationToken);
        return profile;
    }

    public async Task<GuestProfile> UnsaveDiscoveryAsync(Guid profileId, string discoveryId, CancellationToken cancellationToken)
    {
        var profile = await GetRequiredAsync(profileId, cancellationToken);
        profile.RemoveDiscovery(discoveryId);
        await _profiles.UpdateAsync(profile, cancellationToken);
        return profile;
    }

    public async Task<GuestProfile> RecordPreferenceSignalAsync(Guid profileId, PreferenceSignalCommand command, CancellationToken cancellationToken)
    {
        var profile = await GetRequiredAsync(profileId, cancellationToken);
        profile.RecordSignal(new PreferenceSignal(Guid.NewGuid(), command.Topic.Trim(), Math.Clamp(command.Weight, -3, 3), command.Reason.Trim(), _timeProvider.GetUtcNow()));
        await _profiles.UpdateAsync(profile, cancellationToken);
        return profile;
    }

    public async Task<GuestProfile> RecordStoryInteractionAsync(Guid profileId, StoryInteractionCommand command, CancellationToken cancellationToken)
    {
        var profile = await GetRequiredAsync(profileId, cancellationToken);
        if (!_phase15Options.Enabled || !_phase15Options.InteractionMemoryEnabled)
        {
            return profile;
        }
        if (string.IsNullOrWhiteSpace(command.EventId)
            || string.IsNullOrWhiteSpace(command.StoryId)
            || string.IsNullOrWhiteSpace(command.Category)
            || !Enum.TryParse<StoryInteractionKind>(command.Kind, true, out var kind))
        {
            throw new ArgumentException("Story interaction event, story, category and supported kind are required.", nameof(command));
        }

        var now = _timeProvider.GetUtcNow();
        var occurredAt = command.OccurredAtUtc is { } requested
            && requested <= now.AddMinutes(5)
            && requested >= now.AddDays(-Math.Max(1, _phase15Options.InteractionRetentionDays))
                ? requested
                : now;
        var category = NormalizeCategory(command.Category);
        var added = profile.RecordStoryInteraction(
            new StoryInteraction(command.EventId.Trim(), command.StoryId.Trim(), category, kind, occurredAt),
            _phase15Options.MaximumInteractionEventsPerProfile,
            now.AddDays(-Math.Max(1, _phase15Options.InteractionRetentionDays)));
        if (added && InteractionWeight(kind) is { } weight && weight != 0)
        {
            profile.RecordSignal(new PreferenceSignal(
                Guid.NewGuid(),
                category,
                weight,
                $"Story {kind.ToString().ToLowerInvariant()}",
                occurredAt));
        }
        if (added)
        {
            await _profiles.UpdateAsync(profile, cancellationToken);
        }
        return profile;
    }

    public async Task<GuestProfile> RemoveLearnedPreferenceAsync(Guid profileId, string topic, CancellationToken cancellationToken)
    {
        var profile = await GetRequiredAsync(profileId, cancellationToken);
        profile.RemoveLearnedPreference(topic);
        await _profiles.UpdateAsync(profile, cancellationToken);
        return profile;
    }

    public async Task<GuestProfile> ResetLearningAsync(Guid profileId, CancellationToken cancellationToken)
    {
        var profile = await GetRequiredAsync(profileId, cancellationToken);
        profile.ResetLearning();
        await _profiles.UpdateAsync(profile, cancellationToken);
        return profile;
    }

    public Task DeleteAsync(Guid profileId, CancellationToken cancellationToken) => _profiles.DeleteAsync(profileId, cancellationToken);

    private async Task<GuestProfile> GetRequiredAsync(Guid profileId, CancellationToken cancellationToken)
    {
        return await _profiles.GetByIdAsync(profileId, cancellationToken)
            ?? throw new KeyNotFoundException($"Profile '{profileId}' was not found.");
    }

    private int? InteractionWeight(StoryInteractionKind kind) => kind switch
    {
        StoryInteractionKind.Completed => _phase15Options.CompletedStoryWeight,
        StoryInteractionKind.Skipped => _phase15Options.SkippedStoryWeight,
        StoryInteractionKind.Replayed => _phase15Options.ReplayedStoryWeight,
        StoryInteractionKind.TellMore => _phase15Options.TellMoreStoryWeight,
        StoryInteractionKind.Dismissed => _phase15Options.DismissedStoryWeight,
        _ => null
    };

    private static string NormalizeCategory(string category)
    {
        var value = category.Trim().ToLowerInvariant();
        if (value.Length is < 2 or > 40 || value.Any(character => !char.IsLetterOrDigit(character) && character is not '-' and not '_'))
        {
            throw new ArgumentException("Story category must be a short non-sensitive category identifier.", nameof(category));
        }
        return value;
    }
}
