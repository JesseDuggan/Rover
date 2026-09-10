namespace Rover.Api.Contracts;

public sealed record DevelopmentAuthRequest(string? Subject, string? Email, string? InstallationId, Guid? GuestProfileId);

public sealed record DevelopmentAuthResponse(Guid AccountId, string Provider, string Subject, string? Email, string HeaderName, string HeaderValue);

public sealed record LinkGuestProfileRequest(Guid ProfileId);

public sealed record LinkGuestProfileResponse(Guid AccountId, Guid ProfileId, bool Linked, string MergeSummary);

public sealed record AccountResponse(Guid AccountId, string Status, IReadOnlyList<string> Providers, IReadOnlyList<Guid> LinkedProfileIds);
