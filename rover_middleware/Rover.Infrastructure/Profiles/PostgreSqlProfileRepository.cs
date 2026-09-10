using Rover.Application.Profiles;
using Rover.Domain.Profiles;

namespace Rover.Infrastructure.Profiles;

public sealed class PostgreSqlProfileRepository : IProfileRepository
{
    private static InvalidOperationException NotConfigured()
    {
        return new InvalidOperationException("PostgreSQL profile storage requires EF Core/Npgsql packages and a valid Rover:Storage:PostgreSql:ConnectionString. Package restore is currently blocked in this environment.");
    }

    public Task<GuestProfile?> GetByIdAsync(Guid profileId, CancellationToken cancellationToken) => throw NotConfigured();
    public Task<GuestProfile?> GetByInstallationIdAsync(string installationId, CancellationToken cancellationToken) => throw NotConfigured();
    public Task AddAsync(GuestProfile profile, CancellationToken cancellationToken) => throw NotConfigured();
    public Task UpdateAsync(GuestProfile profile, CancellationToken cancellationToken) => throw NotConfigured();
    public Task DeleteAsync(Guid profileId, CancellationToken cancellationToken) => throw NotConfigured();
}
