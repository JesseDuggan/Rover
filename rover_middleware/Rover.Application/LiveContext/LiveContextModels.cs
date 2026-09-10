using System.Collections.Concurrent;
using Rover.Domain.Walks;

namespace Rover.Application.LiveContext;

public enum LiveAutomaticSpeechPolicy
{
    Never,
    UserRequestedOnly,
    Actionable
}

public sealed record ApproximateLiveLocation(
    string? City,
    string? Region,
    string? Country,
    string? TimeZone);

public sealed record LiveContextQuery(
    GeoLocation Location,
    ApproximateLiveLocation ApproximateLocation,
    DateTimeOffset JourneyStartsUtc,
    DateTimeOffset JourneyEndsUtc,
    IReadOnlyCollection<string> Interests,
    bool UserRequested)
{
    public bool ForRouteStory { get; init; }
}

public sealed record LiveSourceReference(
    string ProviderName,
    string? ProviderRecordId,
    string? Title,
    string? Url,
    string Attribution,
    DateTimeOffset RetrievedUtc,
    DateTimeOffset? SourceUpdatedUtc,
    DateTimeOffset ExpiresUtc);

public sealed record LiveWeatherCondition(
    string Condition,
    double? TemperatureCelsius,
    double? FeelsLikeCelsius,
    double? PrecipitationProbabilityPercent,
    double? WindSpeedKilometersPerHour,
    string? WindDirection,
    DateTimeOffset ObservedUtc,
    bool MeaningfulChange,
    LiveAutomaticSpeechPolicy AutomaticSpeechPolicy,
    LiveSourceReference Source);

public sealed record LiveWeatherAlert(
    string AlertId,
    string Title,
    string Summary,
    string? Severity,
    DateTimeOffset? StartsUtc,
    DateTimeOffset? EndsUtc,
    LiveAutomaticSpeechPolicy AutomaticSpeechPolicy,
    LiveSourceReference Source);

public sealed record LiveEvent(
    string EventId,
    string Name,
    string? VenueName,
    string? Address,
    DateTimeOffset StartsUtc,
    DateTimeOffset? EndsUtc,
    string? Category,
    double? Latitude,
    double? Longitude,
    LiveAutomaticSpeechPolicy AutomaticSpeechPolicy,
    LiveSourceReference Source);

public sealed record LiveCurrentInformation(
    string InformationId,
    string Summary,
    string Category,
    LiveAutomaticSpeechPolicy AutomaticSpeechPolicy,
    IReadOnlyList<LiveSourceReference> Sources);

public sealed record LiveProviderResult<T>(
    string ProviderName,
    bool Enabled,
    bool Succeeded,
    IReadOnlyList<T> Items,
    DateTimeOffset RetrievedUtc,
    DateTimeOffset ExpiresUtc,
    string? Warning)
{
    public static LiveProviderResult<T> Disabled(string providerName, DateTimeOffset now) =>
        new(providerName, false, true, Array.Empty<T>(), now, now, null);

    public static LiveProviderResult<T> Failed(string providerName, DateTimeOffset now, TimeSpan retryAfter, string warning) =>
        new(providerName, true, false, Array.Empty<T>(), now, now.Add(retryAfter), warning);
}

public sealed record LiveJourneyContext(
    DateTimeOffset GeneratedUtc,
    DateTimeOffset ExpiresUtc,
    LiveProviderResult<LiveWeatherCondition> Weather,
    LiveProviderResult<LiveWeatherAlert> WeatherAlerts,
    LiveProviderResult<LiveEvent> Events,
    LiveProviderResult<LiveCurrentInformation> CurrentInformation,
    bool CacheHit);

public interface ILiveWeatherProvider
{
    Task<(LiveProviderResult<LiveWeatherCondition> Conditions, LiveProviderResult<LiveWeatherAlert> Alerts)> GetAsync(
        LiveContextQuery query,
        CancellationToken cancellationToken);
}

public interface ILiveEventProvider
{
    Task<LiveProviderResult<LiveEvent>> GetAsync(LiveContextQuery query, CancellationToken cancellationToken);
}

public interface ILiveCurrentInformationProvider
{
    Task<LiveProviderResult<LiveCurrentInformation>> GetAsync(LiveContextQuery query, CancellationToken cancellationToken);
}

public interface ILiveJourneyContextService
{
    Task<LiveJourneyContext> GetAsync(LiveContextQuery query, CancellationToken cancellationToken);
}

public interface ILiveContextStore
{
    bool TryGet(string key, DateTimeOffset now, out LiveJourneyContext? context);
    void Store(string key, LiveJourneyContext context);
}

public sealed class InMemoryLiveContextStore : ILiveContextStore
{
    private readonly ConcurrentDictionary<string, LiveJourneyContext> _contexts = new(StringComparer.Ordinal);

    public bool TryGet(string key, DateTimeOffset now, out LiveJourneyContext? context)
    {
        if (_contexts.TryGetValue(key, out var stored) && stored.ExpiresUtc > now)
        {
            context = stored with { CacheHit = true };
            return true;
        }

        _contexts.TryRemove(key, out _);
        context = null;
        return false;
    }

    public void Store(string key, LiveJourneyContext context) => _contexts[key] = context;
}
