namespace Rover.Domain.Accounts;

public sealed class UserAccount
{
    public UserAccount(Guid accountId, DateTimeOffset createdAtUtc, DateTimeOffset updatedAtUtc, string status = "Active")
    {
        AccountId = accountId;
        CreatedAtUtc = createdAtUtc;
        UpdatedAtUtc = updatedAtUtc;
        Status = status;
    }

    public Guid AccountId { get; }
    public DateTimeOffset CreatedAtUtc { get; }
    public DateTimeOffset UpdatedAtUtc { get; private set; }
    public string Status { get; private set; }
    public List<ExternalIdentity> ExternalIdentities { get; } = new();
    public List<GuestProfileLink> GuestProfileLinks { get; } = new();
    public List<DeviceRegistration> Devices { get; } = new();
    public List<SecurityAuditEvent> AuditEvents { get; } = new();
    public uint Version { get; private set; }

    public void Touch(DateTimeOffset updatedAtUtc)
    {
        UpdatedAtUtc = updatedAtUtc;
        Version++;
    }

    public void AddIdentity(ExternalIdentity identity)
    {
        if (ExternalIdentities.Any(item =>
                item.Provider.Equals(identity.Provider, StringComparison.OrdinalIgnoreCase)
                && item.Subject.Equals(identity.Subject, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }

        ExternalIdentities.Add(identity);
        Version++;
    }

    public void LinkGuestProfile(Guid profileId, DateTimeOffset linkedAtUtc)
    {
        if (GuestProfileLinks.Any(item => item.ProfileId == profileId))
        {
            return;
        }

        GuestProfileLinks.Add(new GuestProfileLink(Guid.NewGuid(), AccountId, profileId, linkedAtUtc));
        Version++;
    }

    public void AddAudit(string eventType, string outcome, DateTimeOffset occurredAtUtc)
    {
        AuditEvents.Add(new SecurityAuditEvent(Guid.NewGuid(), AccountId, eventType, outcome, occurredAtUtc));
        Version++;
    }

    public void RequestDeletion(DateTimeOffset requestedAtUtc)
    {
        Status = "DeletionRequested";
        AddAudit("AccountDeletionRequested", "Accepted", requestedAtUtc);
    }
}

public sealed record ExternalIdentity(
    Guid ExternalIdentityId,
    Guid AccountId,
    string Provider,
    string Subject,
    string? VerifiedEmail,
    DateTimeOffset CreatedAtUtc,
    DateTimeOffset UpdatedAtUtc);

public sealed record GuestProfileLink(Guid GuestProfileLinkId, Guid AccountId, Guid ProfileId, DateTimeOffset LinkedAtUtc);

public sealed record DeviceRegistration(Guid DeviceRegistrationId, Guid AccountId, string InstallationId, DateTimeOffset CreatedAtUtc, DateTimeOffset LastSeenAtUtc);

public sealed record AccountDeletionRequest(Guid AccountDeletionRequestId, Guid AccountId, DateTimeOffset RequestedAtUtc, string Status);

public sealed record SecurityAuditEvent(Guid SecurityAuditEventId, Guid AccountId, string EventType, string Outcome, DateTimeOffset OccurredAtUtc);
