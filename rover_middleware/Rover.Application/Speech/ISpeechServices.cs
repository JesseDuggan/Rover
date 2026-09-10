namespace Rover.Application.Speech;

public interface IRoverSpeechService
{
    Task<RenderedSpeech> RenderAsync(RenderSpeechCommand command, string correlationId, CancellationToken cancellationToken);
}

public interface ITextToSpeechProvider
{
    string Name { get; }
    Task<RenderedSpeech> RenderAsync(PreparedSpeechText text, string correlationId, CancellationToken cancellationToken);
}

public interface IGeneratedAudioCache
{
    Task<RenderedSpeech?> GetAsync(SpeechCacheKey key, string correlationId, CancellationToken cancellationToken);
    Task SetAsync(SpeechCacheKey key, RenderedSpeech speech, CancellationToken cancellationToken);
}

public interface ISpeechUsageService
{
    Task RecordAsync(SpeechUsageEvent usage, CancellationToken cancellationToken);
    Task<bool> CanRenderAsync(Guid accountId, SpeechPurpose purpose, int characterCount, CancellationToken cancellationToken);
}

public sealed record PreparedSpeechText(string Text, SpeechPurpose Purpose, string Locale, string ContentVersion);

public sealed record SpeechCacheKey(
    string TextHash,
    string VoiceId,
    string ModelId,
    string OutputFormat,
    string VoiceSettingsHash,
    string Locale,
    string ContentVersion)
{
    public DateTimeOffset? ExpiresUtc { get; init; }
    public string? StoryId { get; init; }
    public string? VariantId { get; init; }
}
