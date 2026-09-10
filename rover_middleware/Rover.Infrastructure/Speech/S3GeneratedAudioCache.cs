using Rover.Application.Speech;

namespace Rover.Infrastructure.Speech;

public sealed class S3GeneratedAudioCache : IGeneratedAudioCache
{
    public Task<RenderedSpeech?> GetAsync(SpeechCacheKey key, string correlationId, CancellationToken cancellationToken)
    {
        throw new InvalidOperationException("S3 generated-audio cache is reserved for the AWS staging pass. Use FileGeneratedAudioCache locally.");
    }

    public Task SetAsync(SpeechCacheKey key, RenderedSpeech speech, CancellationToken cancellationToken)
    {
        throw new InvalidOperationException("S3 generated-audio cache is reserved for the AWS staging pass. Use FileGeneratedAudioCache locally.");
    }
}
