using System.Collections.Concurrent;
using Rover.Application.LocationIntelligence;

namespace Rover.Infrastructure.LocationIntelligence;

public sealed class InMemoryLocationContextCache : ILocationContextCache
{
    private readonly ConcurrentDictionary<string, CacheEntry> _entries = new(StringComparer.OrdinalIgnoreCase);
    private readonly TimeProvider _timeProvider;

    public InMemoryLocationContextCache(TimeProvider timeProvider)
    {
        _timeProvider = timeProvider;
    }

    public bool TryGet<T>(string key, out T? value)
    {
        value = default;
        if (!_entries.TryGetValue(key, out var entry))
        {
            return false;
        }

        if (entry.ExpiresUtc <= _timeProvider.GetUtcNow())
        {
            _entries.TryRemove(key, out _);
            return false;
        }

        if (entry.Value is not T typed)
        {
            return false;
        }

        value = typed;
        return true;
    }

    public void Set<T>(string key, T value, TimeSpan duration)
    {
        _entries[key] = new CacheEntry(value, _timeProvider.GetUtcNow().Add(duration));
    }

    private sealed record CacheEntry(object? Value, DateTimeOffset ExpiresUtc);
}
