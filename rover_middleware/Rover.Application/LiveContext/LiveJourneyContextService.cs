using System.Globalization;

namespace Rover.Application.LiveContext;

public sealed class LiveJourneyContextService : ILiveJourneyContextService
{
    private readonly ILiveWeatherProvider _weatherProvider;
    private readonly ILiveEventProvider _eventProvider;
    private readonly ILiveCurrentInformationProvider _currentInformationProvider;
    private readonly ILiveContextStore _store;
    private readonly TimeProvider _timeProvider;

    public LiveJourneyContextService(
        ILiveWeatherProvider weatherProvider,
        ILiveEventProvider eventProvider,
        ILiveCurrentInformationProvider currentInformationProvider,
        ILiveContextStore store,
        TimeProvider timeProvider)
    {
        _weatherProvider = weatherProvider;
        _eventProvider = eventProvider;
        _currentInformationProvider = currentInformationProvider;
        _store = store;
        _timeProvider = timeProvider;
    }

    public async Task<LiveJourneyContext> GetAsync(LiveContextQuery query, CancellationToken cancellationToken)
    {
        Validate(query);
        var now = _timeProvider.GetUtcNow();
        var key = CacheKey(query);
        if (_store.TryGet(key, now, out var cached))
        {
            return cached!;
        }

        var weatherTask = SafeWeatherAsync(query, now, cancellationToken);
        var eventsTask = SafeEventsAsync(query, now, cancellationToken);
        var currentTask = SafeCurrentInformationAsync(query, now, cancellationToken);
        await Task.WhenAll(weatherTask, eventsTask, currentTask);

        var weather = await weatherTask;
        var events = await eventsTask;
        var current = await currentTask;
        var expires = new[]
            {
                weather.Conditions.ExpiresUtc,
                weather.Alerts.ExpiresUtc,
                events.ExpiresUtc,
                current.ExpiresUtc
            }
            .Where(value => value > now)
            .DefaultIfEmpty(now.AddMinutes(2))
            .Min();
        var context = new LiveJourneyContext(
            now,
            expires,
            weather.Conditions,
            weather.Alerts,
            events,
            current,
            false);
        _store.Store(key, context);
        return context;
    }

    private async Task<(LiveProviderResult<LiveWeatherCondition> Conditions, LiveProviderResult<LiveWeatherAlert> Alerts)> SafeWeatherAsync(
        LiveContextQuery query,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        try
        {
            return await _weatherProvider.GetAsync(query, cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            return (
                LiveProviderResult<LiveWeatherCondition>.Failed("Google Weather", now, TimeSpan.FromMinutes(2), "Live weather is temporarily unavailable."),
                LiveProviderResult<LiveWeatherAlert>.Failed("Google Weather", now, TimeSpan.FromMinutes(2), "Weather alerts are temporarily unavailable."));
        }
    }

    private async Task<LiveProviderResult<LiveEvent>> SafeEventsAsync(LiveContextQuery query, DateTimeOffset now, CancellationToken cancellationToken)
    {
        try
        {
            return await _eventProvider.GetAsync(query, cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            return LiveProviderResult<LiveEvent>.Failed("Ticketmaster Discovery", now, TimeSpan.FromMinutes(2), "Live events are temporarily unavailable.");
        }
    }

    private async Task<LiveProviderResult<LiveCurrentInformation>> SafeCurrentInformationAsync(
        LiveContextQuery query,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        try
        {
            return await _currentInformationProvider.GetAsync(query, cancellationToken);
        }
        catch (Exception exception) when (exception is not OperationCanceledException || !cancellationToken.IsCancellationRequested)
        {
            return LiveProviderResult<LiveCurrentInformation>.Failed("OpenAI web search", now, TimeSpan.FromMinutes(2), "Current local information is temporarily unavailable.");
        }
    }

    private static void Validate(LiveContextQuery query)
    {
        if (query.Location.Latitude is < -90 or > 90 || query.Location.Longitude is < -180 or > 180)
        {
            throw new ArgumentException("Live context requires valid latitude and longitude.");
        }

        if (query.JourneyEndsUtc <= query.JourneyStartsUtc)
        {
            throw new ArgumentException("Journey end time must be after its start time.");
        }
    }

    private static string CacheKey(LiveContextQuery query)
    {
        var interests = string.Join(',', query.Interests.OrderBy(value => value, StringComparer.OrdinalIgnoreCase));
        return string.Join('|',
            Math.Round(query.Location.Latitude, 3).ToString("F3", CultureInfo.InvariantCulture),
            Math.Round(query.Location.Longitude, 3).ToString("F3", CultureInfo.InvariantCulture),
            query.JourneyEndsUtc.UtcDateTime.ToString("yyyyMMddHH", CultureInfo.InvariantCulture),
            query.ApproximateLocation.City?.Trim().ToLowerInvariant(),
            interests,
            query.UserRequested,
            query.ForRouteStory);
    }
}

public sealed class DisabledLiveWeatherProvider(TimeProvider timeProvider) : ILiveWeatherProvider
{
    public Task<(LiveProviderResult<LiveWeatherCondition>, LiveProviderResult<LiveWeatherAlert>)> GetAsync(
        LiveContextQuery query,
        CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        return Task.FromResult((
            LiveProviderResult<LiveWeatherCondition>.Disabled("Google Weather", now),
            LiveProviderResult<LiveWeatherAlert>.Disabled("Google Weather", now)));
    }
}

public sealed class DisabledLiveEventProvider(TimeProvider timeProvider) : ILiveEventProvider
{
    public Task<LiveProviderResult<LiveEvent>> GetAsync(LiveContextQuery query, CancellationToken cancellationToken) =>
        Task.FromResult(LiveProviderResult<LiveEvent>.Disabled("Ticketmaster Discovery", timeProvider.GetUtcNow()));
}

public sealed class DisabledLiveCurrentInformationProvider(TimeProvider timeProvider) : ILiveCurrentInformationProvider
{
    public Task<LiveProviderResult<LiveCurrentInformation>> GetAsync(LiveContextQuery query, CancellationToken cancellationToken) =>
        Task.FromResult(LiveProviderResult<LiveCurrentInformation>.Disabled("OpenAI web search", timeProvider.GetUtcNow()));
}
