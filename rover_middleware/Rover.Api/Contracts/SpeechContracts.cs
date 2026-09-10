namespace Rover.Api.Contracts;

public sealed record RenderSpeechRequest(
    string? Text,
    string? Purpose,
    string? Locale,
    string? WalkSessionId,
    string? StopId,
    string? IdempotencyKey)
{
    public bool? CacheEligible { get; init; }
    public DateTimeOffset? CacheExpiresUtc { get; init; }
    public string? StoryId { get; init; }
    public string? VariantId { get; init; }
}
