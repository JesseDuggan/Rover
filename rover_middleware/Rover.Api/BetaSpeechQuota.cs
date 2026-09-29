namespace Rover.Api;

// A quota identity only: this does not create an account or grant profile access.
internal static class BetaSpeechQuota
{
    internal static readonly Guid AccountId = new("e73f047d-527e-4f19-9a16-38d05de801cc");
    internal static readonly SemaphoreSlim Gate = new(1, 1);
}
