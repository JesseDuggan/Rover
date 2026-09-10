namespace Rover.Application.Accounts;

public sealed record ExternalIdentityCommand(string Provider, string Subject, string? VerifiedEmail);

public sealed record LinkGuestProfileCommand(Guid ProfileId);

public sealed record AccountMergeResult(Guid AccountId, Guid ProfileId, bool Linked, string MergeSummary);
