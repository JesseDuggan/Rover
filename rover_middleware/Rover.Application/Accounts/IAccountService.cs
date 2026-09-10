using Rover.Domain.Accounts;

namespace Rover.Application.Accounts;

public interface IAccountService
{
    Task<UserAccount> CreateOrGetExternalAccountAsync(ExternalIdentityCommand command, CancellationToken cancellationToken);
    Task<UserAccount?> GetAsync(Guid accountId, CancellationToken cancellationToken);
    Task<AccountMergeResult> LinkGuestProfileAsync(Guid accountId, LinkGuestProfileCommand command, CancellationToken cancellationToken);
    Task<bool> CanAccessProfileAsync(Guid accountId, Guid profileId, CancellationToken cancellationToken);
    Task<object> ExportAsync(Guid accountId, CancellationToken cancellationToken);
    Task RequestDeletionAsync(Guid accountId, CancellationToken cancellationToken);
}
