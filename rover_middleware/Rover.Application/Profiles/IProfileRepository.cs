using Rover.Domain.Profiles;

namespace Rover.Application.Profiles;

public interface IProfileRepository
{
    Task<GuestProfile?> GetByIdAsync(Guid profileId, CancellationToken cancellationToken);
    Task<GuestProfile?> GetByInstallationIdAsync(string installationId, CancellationToken cancellationToken);
    Task AddAsync(GuestProfile profile, CancellationToken cancellationToken);
    Task UpdateAsync(GuestProfile profile, CancellationToken cancellationToken);
    Task DeleteAsync(Guid profileId, CancellationToken cancellationToken);
}
