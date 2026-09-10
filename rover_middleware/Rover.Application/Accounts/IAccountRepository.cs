using Rover.Domain.Accounts;

namespace Rover.Application.Accounts;

public interface IAccountRepository
{
    Task<UserAccount?> GetByIdAsync(Guid accountId, CancellationToken cancellationToken);
    Task<UserAccount?> GetByExternalIdentityAsync(string provider, string subject, CancellationToken cancellationToken);
    Task<UserAccount?> GetByProfileIdAsync(Guid profileId, CancellationToken cancellationToken);
    Task AddAsync(UserAccount account, CancellationToken cancellationToken);
    Task UpdateAsync(UserAccount account, CancellationToken cancellationToken);
    Task DeleteAsync(Guid accountId, CancellationToken cancellationToken);
}
