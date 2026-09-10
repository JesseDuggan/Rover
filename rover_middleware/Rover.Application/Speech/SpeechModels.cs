namespace Rover.Application.Speech;

public enum SpeechPurpose
{
    StopNarration,
    AskRoverAnswer,
    WalkIntroduction,
    WalkRecap,
    DiscoveryDescription
}

public sealed record RenderSpeechCommand(
    Guid AccountId,
    string Text,
    SpeechPurpose Purpose,
    string? Locale,
    string? WalkSessionId,
    string? StopId,
    string? IdempotencyKey)
{
    public bool CacheEligible { get; init; }
    public DateTimeOffset? CacheExpiresUtc { get; init; }
    public string? StoryId { get; init; }
    public string? VariantId { get; init; }
}

public sealed record RenderedSpeech(
    byte[] Audio,
    string ContentType,
    string Provider,
    bool CacheHit,
    bool UsedFallback,
    string CorrelationId,
    string? FallbackReason = null);

public sealed record SpeechUsageEvent(
    Guid AccountId,
    SpeechPurpose Purpose,
    int CharacterCount,
    bool CacheHit,
    bool Success,
    long ProviderLatencyMs,
    DateTimeOffset CreatedAtUtc);
