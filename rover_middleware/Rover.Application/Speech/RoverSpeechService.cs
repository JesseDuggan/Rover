using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;

namespace Rover.Application.Speech;

public sealed class RoverSpeechService : IRoverSpeechService
{
    private readonly ITextToSpeechProvider _primaryProvider;
    private readonly ITextToSpeechProvider _fallbackProvider;
    private readonly IGeneratedAudioCache _cache;
    private readonly ISpeechUsageService _usage;
    private readonly ElevenLabsSpeechOptions _options;
    private readonly TimeProvider _timeProvider;

    public RoverSpeechService(
        ITextToSpeechProvider primaryProvider,
        DevelopmentFakeSpeechProvider fallbackProvider,
        IGeneratedAudioCache cache,
        ISpeechUsageService usage,
        ElevenLabsSpeechOptions options,
        TimeProvider timeProvider)
    {
        _primaryProvider = primaryProvider;
        _fallbackProvider = fallbackProvider;
        _cache = cache;
        _usage = usage;
        _options = options;
        _timeProvider = timeProvider;
    }

    public async Task<RenderedSpeech> RenderAsync(RenderSpeechCommand command, string correlationId, CancellationToken cancellationToken)
    {
        var prepared = SpeechTextPreparer.Prepare(command, _options.MaximumCharactersPerRequest);
        if (!await _usage.CanRenderAsync(command.AccountId, command.Purpose, prepared.Text.Length, cancellationToken))
        {
            return await RenderFallbackAsync(command, prepared, correlationId, 0, cancellationToken);
        }

        var cacheKey = CreateCacheKey(prepared, command);
        var reusable = _options.CacheEnabled
            && command.CacheEligible
            && command.Purpose != SpeechPurpose.AskRoverAnswer
            && (command.CacheExpiresUtc is null || command.CacheExpiresUtc > _timeProvider.GetUtcNow());
        if (reusable)
        {
            var cached = await _cache.GetAsync(cacheKey, correlationId, cancellationToken);
            if (cached is not null)
            {
                await RecordAsync(command, prepared, cached, 0, true, cancellationToken);
                return cached;
            }
        }

        var stopwatch = Stopwatch.StartNew();
        try
        {
            var speech = await _primaryProvider.RenderAsync(prepared, correlationId, cancellationToken);
            stopwatch.Stop();
            if (reusable && !speech.UsedFallback)
            {
                await _cache.SetAsync(cacheKey, speech, cancellationToken);
            }

            await RecordAsync(command, prepared, speech, stopwatch.ElapsedMilliseconds, true, cancellationToken);
            return speech;
        }
        catch (Exception exception) when (_options.FallbackEnabled)
        {
            stopwatch.Stop();
            return await RenderFallbackAsync(command, prepared, correlationId, stopwatch.ElapsedMilliseconds, cancellationToken, exception.Message);
        }
    }

    private async Task<RenderedSpeech> RenderFallbackAsync(RenderSpeechCommand command, PreparedSpeechText prepared, string correlationId, long latencyMs, CancellationToken cancellationToken, string? reason = null)
    {
        var speech = await _fallbackProvider.RenderAsync(prepared, correlationId, cancellationToken);
        speech = speech with { UsedFallback = true, FallbackReason = reason };
        await RecordAsync(command, prepared, speech, latencyMs, false, cancellationToken);
        return speech;
    }

    private Task RecordAsync(RenderSpeechCommand command, PreparedSpeechText prepared, RenderedSpeech speech, long latencyMs, bool success, CancellationToken cancellationToken)
    {
        return _usage.RecordAsync(
            new SpeechUsageEvent(command.AccountId, command.Purpose, prepared.Text.Length, speech.CacheHit, success, latencyMs, _timeProvider.GetUtcNow()),
            cancellationToken);
    }

    private SpeechCacheKey CreateCacheKey(PreparedSpeechText text, RenderSpeechCommand command)
    {
        var settings = $"{_options.Stability:F2}|{_options.Similarity:F2}|{_options.Style:F2}|{_options.SpeakerBoost}";
        return new SpeechCacheKey(
            Hash(text.Text),
            _options.VoiceId ?? "development",
            _options.ModelId ?? "development",
            _options.OutputFormat,
            Hash(settings),
            text.Locale,
            text.ContentVersion)
        {
            ExpiresUtc = command.CacheExpiresUtc,
            StoryId = command.StoryId,
            VariantId = command.VariantId
        };
    }

    private static string Hash(string value)
    {
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
    }
}
