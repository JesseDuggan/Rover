using System.Collections.Concurrent;
using Rover.Application.Profiles;
using Rover.Domain.Profiles;

namespace Rover.Infrastructure.Profiles;

public sealed class InMemoryProfileRepository : IProfileRepository
{
    private readonly ConcurrentDictionary<Guid, GuestProfile> _profiles = new();

    public Task<GuestProfile?> GetByIdAsync(Guid profileId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _profiles.TryGetValue(profileId, out var profile);
        return Task.FromResult(profile);
    }

    public Task<GuestProfile?> GetByInstallationIdAsync(string installationId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var profile = _profiles.Values.FirstOrDefault(item => item.InstallationId.Equals(installationId, StringComparison.OrdinalIgnoreCase));
        return Task.FromResult(profile);
    }

    public Task AddAsync(GuestProfile profile, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _profiles.TryAdd(profile.ProfileId, profile);
        return Task.CompletedTask;
    }

    public Task UpdateAsync(GuestProfile profile, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _profiles[profile.ProfileId] = profile;
        return Task.CompletedTask;
    }

    public Task DeleteAsync(Guid profileId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _profiles.TryRemove(profileId, out _);
        return Task.CompletedTask;
    }
}
