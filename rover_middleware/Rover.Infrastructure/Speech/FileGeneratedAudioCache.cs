using System.Text.Json;
using Rover.Application.Speech;

namespace Rover.Infrastructure.Speech;

public sealed class FileGeneratedAudioCache : IGeneratedAudioCache
{
    private readonly ElevenLabsSpeechOptions _options;
    private readonly TimeProvider _timeProvider;

    public FileGeneratedAudioCache(ElevenLabsSpeechOptions options, TimeProvider? timeProvider = null)
    {
        _options = options;
        _timeProvider = timeProvider ?? TimeProvider.System;
    }

    public async Task<RenderedSpeech?> GetAsync(SpeechCacheKey key, string correlationId, CancellationToken cancellationToken)
    {
        var path = PathFor(key);
        var metaPath = $"{path}.json";
        if (!File.Exists(path) || !File.Exists(metaPath))
        {
            return null;
        }

        var metadata = JsonSerializer.Deserialize<CacheMetadata>(await File.ReadAllTextAsync(metaPath, cancellationToken));
        if (metadata is null
            || metadata.ExpiresUtc <= _timeProvider.GetUtcNow()
            || !string.Equals(metadata.ContentVersion, key.ContentVersion, StringComparison.Ordinal))
        {
            Delete(path, metaPath);
            return null;
        }

        var bytes = await File.ReadAllBytesAsync(path, cancellationToken);
        if (bytes.LongLength != metadata.AudioBytes)
        {
            Delete(path, metaPath);
            return null;
        }
        return new RenderedSpeech(bytes, metadata.ContentType, metadata.Provider, true, metadata.UsedFallback, correlationId);
    }

    public async Task SetAsync(SpeechCacheKey key, RenderedSpeech speech, CancellationToken cancellationToken)
    {
        var path = PathFor(key);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        await File.WriteAllBytesAsync(path, speech.Audio, cancellationToken);
        var now = _timeProvider.GetUtcNow();
        var configuredExpiry = now.AddHours(Math.Max(1, _options.CacheRetentionHours));
        var expiresUtc = key.ExpiresUtc is { } requested && requested < configuredExpiry
            ? requested
            : configuredExpiry;
        await File.WriteAllTextAsync(
            $"{path}.json",
            JsonSerializer.Serialize(new CacheMetadata(
                "2.0",
                speech.ContentType,
                speech.Provider,
                speech.UsedFallback,
                now,
                expiresUtc,
                speech.Audio.LongLength,
                key.ContentVersion,
                key.StoryId,
                key.VariantId)),
            cancellationToken);
    }

    private string PathFor(SpeechCacheKey key)
    {
        var root = Path.GetFullPath(_options.CacheDirectory);
        var fileName = $"{key.TextHash}_{key.VoiceId}_{key.ModelId}_{key.OutputFormat}_{key.VoiceSettingsHash}_{key.Locale}_{key.ContentVersion}.mp3";
        foreach (var invalid in Path.GetInvalidFileNameChars())
        {
            fileName = fileName.Replace(invalid, '_');
        }

        return Path.Combine(root, fileName);
    }

    private static void Delete(string path, string metaPath)
    {
        try { File.Delete(path); } catch (IOException) { }
        try { File.Delete(metaPath); } catch (IOException) { }
    }

    private sealed record CacheMetadata(
        string SchemaVersion,
        string ContentType,
        string Provider,
        bool UsedFallback,
        DateTimeOffset StoredUtc,
        DateTimeOffset ExpiresUtc,
        long AudioBytes,
        string ContentVersion,
        string? StoryId,
        string? VariantId);
}
