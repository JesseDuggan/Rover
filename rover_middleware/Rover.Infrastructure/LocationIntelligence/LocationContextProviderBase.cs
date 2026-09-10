using System.Diagnostics;
using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.LocationIntelligence;

public abstract class LocationContextProviderBase : ILocationContextProvider
{
    private readonly ILocationContextCache _cache;
    private readonly TimeProvider _timeProvider;
    private readonly LocationProviderOptions _options;

    protected LocationContextProviderBase(ILocationContextCache cache, TimeProvider timeProvider, LocationProviderOptions options)
    {
        _cache = cache;
        _timeProvider = timeProvider;
        _options = options;
    }

    public abstract string Name { get; }

    protected DateTimeOffset Now => _timeProvider.GetUtcNow();
    protected LocationProviderOptions Options => _options;
    protected virtual bool AllowResultCaching => true;

    public async Task<LocationContextProviderResult> GetContextAsync(LocationContextQuery query, CancellationToken cancellationToken)
    {
        if (!_options.Enabled)
        {
            return new LocationContextProviderResult(Name, false, Array.Empty<LocationPlace>(), null, Array.Empty<string>(), false, 0);
        }

        var cacheKey = $"{Name}:{Math.Round(query.UserLocation.Latitude, 3):F3}:{Math.Round(query.UserLocation.Longitude, 3):F3}:{query.RadiusMeters}:{string.Join(",", query.Interests)}";
        if (AllowResultCaching && _cache.TryGet<LocationContextProviderResult>(cacheKey, out var cached) && cached is not null)
        {
            return cached with { CacheHit = true };
        }

        var stopwatch = Stopwatch.StartNew();
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(Math.Clamp(_options.TimeoutSeconds, 2, 30)));

        try
        {
            var result = await FetchAsync(query, timeout.Token);
            stopwatch.Stop();
            result = result with { LatencyMilliseconds = stopwatch.ElapsedMilliseconds };
            if (AllowResultCaching)
            {
                _cache.Set(cacheKey, result, TimeSpan.FromMinutes(Math.Max(1, _options.CacheMinutes)));
            }
            return result;
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            stopwatch.Stop();
            return new LocationContextProviderResult(Name, true, Array.Empty<LocationPlace>(), null, new[] { $"{Name} timed out." }, false, stopwatch.ElapsedMilliseconds);
        }
    }

    protected abstract Task<LocationContextProviderResult> FetchAsync(LocationContextQuery query, CancellationToken cancellationToken);

    protected LocationSource Source(string? recordId, string? sourceUrl, string attribution, string? license, double confidence)
    {
        return new LocationSource(Name, recordId, sourceUrl, attribution, license, Now, confidence);
    }

    protected static LocationPlace Place(
        string canonicalId,
        string name,
        GeoLocation coordinates,
        string? address,
        IReadOnlyList<string> categories,
        string? shortDescription,
        IReadOnlyList<LocationFact> facts,
        IReadOnlyList<LocationSource> sources,
        IReadOnlyDictionary<string, string> providerIds,
        double confidence,
        DateTimeOffset refreshedUtc,
        string? openingStatus = null,
        string? accessibilityInformation = null)
    {
        return new LocationPlace(
            canonicalId,
            name,
            coordinates,
            address,
            categories,
            shortDescription,
            facts,
            sources,
            providerIds,
            null,
            null,
            null,
            null,
            confidence,
            0,
            Array.Empty<string>(),
            Array.Empty<LocationImageReference>(),
            openingStatus,
            accessibilityInformation,
            refreshedUtc);
    }
}
