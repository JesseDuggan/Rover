using Rover.Application.Profiles;
using Rover.Domain.Accounts;

namespace Rover.Application.Accounts;

public sealed class AccountService : IAccountService
{
    private readonly IAccountRepository _accounts;
    private readonly IProfileRepository _profiles;
    private readonly TimeProvider _timeProvider;

    public AccountService(IAccountRepository accounts, IProfileRepository profiles, TimeProvider timeProvider)
    {
        _accounts = accounts;
        _profiles = profiles;
        _timeProvider = timeProvider;
    }

    public async Task<UserAccount> CreateOrGetExternalAccountAsync(ExternalIdentityCommand command, CancellationToken cancellationToken)
    {
        var provider = Require(command.Provider, "Provider");
        var subject = Require(command.Subject, "Subject");
        var existing = await _accounts.GetByExternalIdentityAsync(provider, subject, cancellationToken);
        if (existing is not null)
        {
            existing.AddAudit("SignIn", "Success", _timeProvider.GetUtcNow());
            await _accounts.UpdateAsync(existing, cancellationToken);
            return existing;
        }

        var now = _timeProvider.GetUtcNow();
        var account = new UserAccount(Guid.NewGuid(), now, now);
        account.AddIdentity(new ExternalIdentity(Guid.NewGuid(), account.AccountId, provider, subject, CleanEmail(command.VerifiedEmail), now, now));
        account.AddAudit("AccountCreated", "Success", now);
        await _accounts.AddAsync(account, cancellationToken);
        return account;
    }

    public Task<UserAccount?> GetAsync(Guid accountId, CancellationToken cancellationToken)
    {
        return _accounts.GetByIdAsync(accountId, cancellationToken);
    }

    public async Task<AccountMergeResult> LinkGuestProfileAsync(Guid accountId, LinkGuestProfileCommand command, CancellationToken cancellationToken)
    {
        var account = await _accounts.GetByIdAsync(accountId, cancellationToken)
            ?? throw new KeyNotFoundException($"Account '{accountId}' was not found.");
        var profile = await _profiles.GetByIdAsync(command.ProfileId, cancellationToken)
            ?? throw new KeyNotFoundException($"Profile '{command.ProfileId}' was not found.");
        var owner = await _accounts.GetByProfileIdAsync(command.ProfileId, cancellationToken);
        if (owner is not null && owner.AccountId != accountId)
        {
            throw new InvalidOperationException("Guest profile is already linked to another account.");
        }

        var wasLinked = account.GuestProfileLinks.Any(item => item.ProfileId == command.ProfileId);
        account.LinkGuestProfile(command.ProfileId, _timeProvider.GetUtcNow());
        account.AddAudit("GuestProfileLinked", wasLinked ? "AlreadyLinked" : "Success", _timeProvider.GetUtcNow());
        await _accounts.UpdateAsync(account, cancellationToken);
        return new AccountMergeResult(account.AccountId, profile.ProfileId, !wasLinked, wasLinked ? "Guest data was already linked." : "Guest preferences, saved discoveries and learned signals were preserved.");
    }

    public async Task<bool> CanAccessProfileAsync(Guid accountId, Guid profileId, CancellationToken cancellationToken)
    {
        var owner = await _accounts.GetByProfileIdAsync(profileId, cancellationToken);
        return owner is null || owner.AccountId == accountId;
    }

    public async Task<object> ExportAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var account = await _accounts.GetByIdAsync(accountId, cancellationToken)
            ?? throw new KeyNotFoundException($"Account '{accountId}' was not found.");
        var profiles = new List<object>();
        foreach (var link in account.GuestProfileLinks)
        {
            var profile = await _profiles.GetByIdAsync(link.ProfileId, cancellationToken);
            if (profile is not null)
            {
                profiles.Add(new
                {
                    profile.ProfileId,
                    profile.InstallationId,
                    profile.CreatedAtUtc,
                    profile.UpdatedAtUtc,
                    profile.Preferences,
                    profile.SavedDiscoveries,
                    profile.LearnedPreferences
                });
            }
        }

        return new
        {
            account.AccountId,
            account.Status,
            account.CreatedAtUtc,
            ExternalIdentities = account.ExternalIdentities.Select(identity => new
            {
                identity.Provider,
                identity.Subject,
                identity.VerifiedEmail,
                identity.CreatedAtUtc,
                identity.UpdatedAtUtc
            }),
            Profiles = profiles,
            AuditEvents = account.AuditEvents.Select(audit => new
            {
                audit.EventType,
                audit.Outcome,
                audit.OccurredAtUtc
            })
        };
    }

    public async Task RequestDeletionAsync(Guid accountId, CancellationToken cancellationToken)
    {
        var account = await _accounts.GetByIdAsync(accountId, cancellationToken)
            ?? throw new KeyNotFoundException($"Account '{accountId}' was not found.");
        var now = _timeProvider.GetUtcNow();
        account.RequestDeletion(now);
        foreach (var link in account.GuestProfileLinks)
        {
            await _profiles.DeleteAsync(link.ProfileId, cancellationToken);
        }

        await _accounts.DeleteAsync(accountId, cancellationToken);
    }

    private static string Require(string value, string name)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException($"{name} is required.");
        }

        return value.Trim();
    }

    private static string? CleanEmail(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim().ToLowerInvariant();
    }
}
