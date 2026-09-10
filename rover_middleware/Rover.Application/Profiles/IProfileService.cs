using Rover.Domain.Profiles;

namespace Rover.Application.Profiles;

public interface IProfileService
{
    Task<GuestProfile> CreateOrGetGuestAsync(CreateGuestProfileCommand command, CancellationToken cancellationToken);
    Task<GuestProfile?> GetAsync(Guid profileId, CancellationToken cancellationToken);
    Task<GuestProfile> UpdatePreferencesAsync(Guid profileId, UpdateUserPreferencesCommand command, CancellationToken cancellationToken);
    Task<GuestProfile> SaveDiscoveryAsync(Guid profileId, SaveDiscoveryCommand command, CancellationToken cancellationToken);
    Task<GuestProfile> UnsaveDiscoveryAsync(Guid profileId, string discoveryId, CancellationToken cancellationToken);
    Task<GuestProfile> RecordPreferenceSignalAsync(Guid profileId, PreferenceSignalCommand command, CancellationToken cancellationToken);
    Task<GuestProfile> RecordStoryInteractionAsync(Guid profileId, StoryInteractionCommand command, CancellationToken cancellationToken);
    Task<GuestProfile> RemoveLearnedPreferenceAsync(Guid profileId, string topic, CancellationToken cancellationToken);
    Task<GuestProfile> ResetLearningAsync(Guid profileId, CancellationToken cancellationToken);
    Task DeleteAsync(Guid profileId, CancellationToken cancellationToken);
}
