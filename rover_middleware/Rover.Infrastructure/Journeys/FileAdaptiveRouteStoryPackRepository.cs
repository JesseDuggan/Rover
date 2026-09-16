using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Rover.Application.Journeys;
using Rover.Application.LocationIntelligence;

namespace Rover.Infrastructure.Journeys;

public sealed class FileAdaptiveRouteStoryPackRepository : IAdaptiveRouteStoryPackRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true,
        Converters = { new StoryIdSetConverter() }
    };

    private readonly ConcurrentDictionary<string, AdaptiveRouteStoryPackState> _memory = new(StringComparer.OrdinalIgnoreCase);
    private readonly LocationIntelligenceOptions _storageOptions;
    private readonly TimeProvider _timeProvider;
    private readonly SemaphoreSlim _gate = new(1, 1);

    public FileAdaptiveRouteStoryPackRepository(LocationIntelligenceOptions storageOptions, TimeProvider timeProvider)
    {
        _storageOptions = storageOptions;
        _timeProvider = timeProvider;
    }

    public async Task<AdaptiveRouteStoryPackState?> GetAsync(
        string walkSessionId,
        int routeRevision,
        CancellationToken cancellationToken)
    {
        var key = Key(walkSessionId, routeRevision);
        if (_memory.TryGetValue(key, out var current))
        {
            return current;
        }
        if (!_storageOptions.PersistentStorageEnabled)
        {
            return null;
        }

        await _gate.WaitAsync(cancellationToken);
        try
        {
            if (!File.Exists(PathFor(key)))
            {
                return null;
            }
            try
            {
                await using var stream = File.OpenRead(PathFor(key));
                var stored = await JsonSerializer.DeserializeAsync<AdaptiveRouteStoryPackState>(stream, JsonOptions, cancellationToken);
                if (stored?.Pack is null
                    || stored.RouteRevision != routeRevision
                    || !stored.WalkSessionId.Equals(walkSessionId, StringComparison.OrdinalIgnoreCase)
                    || stored.Pack.ExpiresUtc <= _timeProvider.GetUtcNow())
                {
                    DeleteIfExists(PathFor(key));
                    return null;
                }
                _memory[key] = stored;
                return stored;
            }
            catch (Exception exception) when (exception is JsonException or IOException or NotSupportedException)
            {
                DeleteIfExists(PathFor(key));
                return null;
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    public async Task StoreAsync(AdaptiveRouteStoryPackState state, CancellationToken cancellationToken)
    {
        var key = Key(state.WalkSessionId, state.RouteRevision);
        _memory[key] = state;
        if (!_storageOptions.PersistentStorageEnabled || state.Pack is null)
        {
            return;
        }

        var durableStories = state.Pack.Stories
            .Where(story => story.ExpiresUtc is null || story.ExpiresUtc > _timeProvider.GetUtcNow())
            .Where(story => story.Sources.Count > 0)
            .Where(story => story.Sources.All(source => source.AllowsOfflineUse && !IsGoogle(source)))
            .ToArray();
        var durable = state with
        {
            Pack = state.Pack with
            {
                Stories = durableStories,
                Collection = durableStories.Length == state.Pack.Stories.Count ? state.Pack.Collection : null,
                Warnings = durableStories.Length == state.Pack.Stories.Count
                    ? state.Pack.Warnings
                    : state.Pack.Warnings.Append("Provider-restricted stories were excluded from offline storage.").ToArray()
            }
        };

        await _gate.WaitAsync(cancellationToken);
        try
        {
            var path = PathFor(key);
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var temporary = $"{path}.{Guid.NewGuid():N}.tmp";
            try
            {
                await using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 16 * 1024, FileOptions.Asynchronous | FileOptions.WriteThrough))
                {
                    await JsonSerializer.SerializeAsync(stream, durable, JsonOptions, cancellationToken);
                    await stream.FlushAsync(cancellationToken);
                }
                File.Move(temporary, path, true);
            }
            finally
            {
                DeleteIfExists(temporary);
            }
        }
        finally
        {
            _gate.Release();
        }
    }

    private string DirectoryPath => Path.Combine(Path.GetFullPath(_storageOptions.PersistentStorageDirectory), "route-story-packs");
    private string PathFor(string key) => Path.Combine(DirectoryPath, $"{Hash(key)}.json");
    private static string Key(string walkSessionId, int routeRevision) => $"{walkSessionId}:{routeRevision}";
    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
    private static bool IsGoogle(AdaptiveStorySource source) => source.ProviderName.Contains("Google", StringComparison.OrdinalIgnoreCase);

    private sealed class StoryIdSetConverter : JsonConverter<IReadOnlySet<string>>
    {
        public override IReadOnlySet<string> Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
        {
            var values = JsonSerializer.Deserialize<string[]>(ref reader, options) ?? Array.Empty<string>();
            return new HashSet<string>(values, StringComparer.OrdinalIgnoreCase);
        }

        public override void Write(Utf8JsonWriter writer, IReadOnlySet<string> value, JsonSerializerOptions options)
            => JsonSerializer.Serialize(writer, value.ToArray(), options);
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
}
