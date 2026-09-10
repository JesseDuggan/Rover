using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Rover.Application.LocationIntelligence;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class FileLocationIntelligenceRepository : IStoryPackRepository, IEvidenceRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    private readonly LocationIntelligenceOptions _options;
    private readonly IStoryPackPersistencePolicy _policy;
    private readonly TimeProvider _timeProvider;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public FileLocationIntelligenceRepository(
        LocationIntelligenceOptions options,
        IStoryPackPersistencePolicy policy,
        TimeProvider timeProvider)
    {
        _options = options;
        _policy = policy;
        _timeProvider = timeProvider;
    }

    public async Task<LocationStoryResult?> GetAsync(StoryPackStorageKey key, CancellationToken cancellationToken)
    {
        if (!_options.PersistentStorageEnabled || !IsValidKey(key))
        {
            return null;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            var path = StoryPath(key);
            var envelope = await ReadAsync<StoredStoryPack>(path, cancellationToken);
            if (envelope is null || !string.Equals(envelope.Key, key.Value, StringComparison.Ordinal))
            {
                DeleteIfExists(path);
                return null;
            }

            var decision = _policy.Prepare(envelope.Story, _timeProvider.GetUtcNow());
            if (!decision.Allowed || decision.Story is null)
            {
                DeleteIfExists(path);
                return null;
            }

            return decision.Story;
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task<bool> StoreAsync(
        StoryPackStorageKey key,
        LocationStoryResult story,
        CancellationToken cancellationToken)
    {
        if (!_options.PersistentStorageEnabled || !IsValidKey(key))
        {
            return false;
        }

        var decision = _policy.Prepare(story, _timeProvider.GetUtcNow());
        if (!decision.Allowed || decision.Story is null)
        {
            return false;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            var path = StoryPath(key);
            await WriteAtomicAsync(
                path,
                new StoredStoryPack(key.Value, decision.Story, _timeProvider.GetUtcNow()),
                cancellationToken);
            Prune(StoryDirectory, Math.Max(1, _options.MaximumStoredStoryPacks));
            return true;
        }
        finally
        {
            _gate.Release();
        }
    }

    async Task<PersistedEvidenceSet?> IEvidenceRepository.GetAsync(
        string canonicalPlaceId,
        CancellationToken cancellationToken)
    {
        if (!_options.PersistentStorageEnabled || string.IsNullOrWhiteSpace(canonicalPlaceId))
        {
            return null;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            var path = EvidencePath(canonicalPlaceId);
            var evidence = await ReadAsync<PersistedEvidenceSet>(path, cancellationToken);
            if (evidence is null
                || !string.Equals(evidence.CanonicalPlaceId, canonicalPlaceId, StringComparison.OrdinalIgnoreCase))
            {
                DeleteIfExists(path);
                return null;
            }

            var now = _timeProvider.GetUtcNow();
            var sources = evidence.Sources
                .Where(source => source.ExpiresUtc is null || source.ExpiresUtc > now)
                .Where(source => !IsGoogle(source))
                .ToArray();
            var sourceIds = sources.Select(source => source.SourceId).ToHashSet(StringComparer.OrdinalIgnoreCase);
            var claims = evidence.Claims
                .Where(claim => claim.ExpiresUtc is null || claim.ExpiresUtc > now)
                .Where(claim => claim.SourceIds.All(sourceIds.Contains))
                .ToArray();
            if (claims.Length == 0)
            {
                DeleteIfExists(path);
                return null;
            }

            return evidence with
            {
                Claims = claims,
                Sources = sources,
                ExpiresUtc = Expiration(claims, sources)
            };
        }
        finally
        {
            _gate.Release();
        }
    }

    async Task<bool> IEvidenceRepository.StoreAsync(StoryPack storyPack, CancellationToken cancellationToken)
    {
        if (!_options.PersistentStorageEnabled)
        {
            return false;
        }

        var now = _timeProvider.GetUtcNow();
        var decision = _policy.Prepare(storyPack, now);
        var prepared = decision.StoryPack;
        if (!decision.Allowed || prepared?.PlaceIdentity is null)
        {
            return false;
        }

        var evidence = new PersistedEvidenceSet(
            prepared.PlaceIdentity.CanonicalPlaceId,
            prepared.SchemaVersion,
            prepared.EvidenceClaims,
            prepared.Sources,
            now,
            Expiration(prepared.EvidenceClaims, prepared.Sources));

        await _gate.WaitAsync(cancellationToken);
        try
        {
            await WriteAtomicAsync(EvidencePath(evidence.CanonicalPlaceId), evidence, cancellationToken);
            Prune(EvidenceDirectory, Math.Max(1, _options.MaximumStoredEvidenceSets));
            return true;
        }
        finally
        {
            _gate.Release();
        }
    }

    private string RootDirectory => Path.GetFullPath(_options.PersistentStorageDirectory);
    private string StoryDirectory => Path.Combine(RootDirectory, "story-packs");
    private string EvidenceDirectory => Path.Combine(RootDirectory, "evidence");
    private string StoryPath(StoryPackStorageKey key) => Path.Combine(StoryDirectory, $"{key.Value}.json");
    private string EvidencePath(string canonicalPlaceId) => Path.Combine(EvidenceDirectory, $"{Hash(canonicalPlaceId)}.json");

    private static bool IsValidKey(StoryPackStorageKey key) =>
        key.Value.Length == 64 && key.Value.All(character => character is >= '0' and <= '9' or >= 'a' and <= 'f');

    private static string Hash(string value) => Convert.ToHexString(
        SHA256.HashData(Encoding.UTF8.GetBytes(value.Trim().ToLowerInvariant()))).ToLowerInvariant();

    private static DateTimeOffset? Expiration(
        IReadOnlyList<EvidenceClaim> claims,
        IReadOnlyList<EvidenceSourceReference> sources)
    {
        var values = claims.Select(claim => claim.ExpiresUtc)
            .Concat(sources.Select(source => source.ExpiresUtc))
            .Where(value => value is not null)
            .Select(value => value!.Value)
            .ToArray();
        return values.Length == 0 ? null : values.Min();
    }

    private static bool IsGoogle(EvidenceSourceReference source) =>
        source.ProviderName.Contains("Google", StringComparison.OrdinalIgnoreCase)
        || source.SourceId.Contains("google", StringComparison.OrdinalIgnoreCase);

    private static async Task<T?> ReadAsync<T>(string path, CancellationToken cancellationToken)
    {
        if (!File.Exists(path))
        {
            return default;
        }

        try
        {
            await using var stream = File.OpenRead(path);
            return await JsonSerializer.DeserializeAsync<T>(stream, JsonOptions, cancellationToken);
        }
        catch (JsonException)
        {
            return default;
        }
        catch (IOException)
        {
            return default;
        }
    }

    private static async Task WriteAtomicAsync<T>(string path, T value, CancellationToken cancellationToken)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporaryPath = $"{path}.{Guid.NewGuid():N}.tmp";
        try
        {
            await using (var stream = new FileStream(
                temporaryPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                16 * 1024,
                FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await JsonSerializer.SerializeAsync(stream, value, JsonOptions, cancellationToken);
                await stream.FlushAsync(cancellationToken);
            }

            File.Move(temporaryPath, path, true);
        }
        finally
        {
            DeleteIfExists(temporaryPath);
        }
    }

    private static void Prune(string directory, int maximumFiles)
    {
        if (!Directory.Exists(directory))
        {
            return;
        }

        foreach (var file in new DirectoryInfo(directory)
                     .EnumerateFiles("*.json")
                     .OrderByDescending(file => file.LastWriteTimeUtc)
                     .Skip(maximumFiles))
        {
            file.Delete();
        }
    }

    private static void DeleteIfExists(string path)
    {
        try
        {
            File.Delete(path);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }

    private sealed record StoredStoryPack(string Key, LocationStoryResult Story, DateTimeOffset StoredUtc);
}
