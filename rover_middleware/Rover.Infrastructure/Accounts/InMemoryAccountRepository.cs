using System.Collections.Concurrent;
using Rover.Application.Accounts;
using Rover.Domain.Accounts;

namespace Rover.Infrastructure.Accounts;

public sealed class InMemoryAccountRepository : IAccountRepository
{
    private readonly ConcurrentDictionary<Guid, UserAccount> _accounts = new();

    public Task<UserAccount?> GetByIdAsync(Guid accountId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _accounts.TryGetValue(accountId, out var account);
        return Task.FromResult(account);
    }

    public Task<UserAccount?> GetByExternalIdentityAsync(string provider, string subject, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var account = _accounts.Values.FirstOrDefault(item =>
            item.ExternalIdentities.Any(identity =>
                identity.Provider.Equals(provider, StringComparison.OrdinalIgnoreCase)
                && identity.Subject.Equals(subject, StringComparison.OrdinalIgnoreCase)));
        return Task.FromResult(account);
    }

    public Task<UserAccount?> GetByProfileIdAsync(Guid profileId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        var account = _accounts.Values.FirstOrDefault(item => item.GuestProfileLinks.Any(link => link.ProfileId == profileId));
        return Task.FromResult(account);
    }

    public Task AddAsync(UserAccount account, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _accounts[account.AccountId] = account;
        return Task.CompletedTask;
    }

    public Task UpdateAsync(UserAccount account, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _accounts[account.AccountId] = account;
        return Task.CompletedTask;
    }

    public Task DeleteAsync(Guid accountId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _accounts.TryRemove(accountId, out _);
        return Task.CompletedTask;
    }
}
