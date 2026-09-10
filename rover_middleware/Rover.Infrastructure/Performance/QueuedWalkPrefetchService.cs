using System.Diagnostics;
using System.Threading.Channels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Rover.Application.Beta;
using Rover.Application.LocationIntelligence;
using Rover.Application.Journeys;
using Rover.Application.Performance;
using Rover.Application.Speech;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Performance;

public sealed class QueuedWalkPrefetchService : BackgroundService, IRoverWalkPrefetchService
{
    private const int Capacity = 32;
    private const int LocationContextRadiusMeters = 1500;
    private readonly Channel<WalkWarmupRequest> _queue = Channel.CreateBounded<WalkWarmupRequest>(
        new BoundedChannelOptions(Capacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false
        });
    private readonly HashSet<string> _queuedKeys = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<QueuedWalkPrefetchService> _logger;
    private readonly Phase15Options _phase15Options;
    private readonly Phase16Options _phase16Options;
    private long _enqueuedCount;
    private long _completedCount;
    private long _failedCount;
    private string? _lastWorkName;
    private long? _lastWorkMilliseconds;
    private string? _lastFailure;

    public QueuedWalkPrefetchService(
        IServiceScopeFactory scopeFactory,
        ILogger<QueuedWalkPrefetchService> logger,
        Phase15Options? phase15Options = null,
        Phase16Options? phase16Options = null)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
        _phase15Options = phase15Options ?? new Phase15Options();
        _phase16Options = phase16Options ?? new Phase16Options();
    }

    public bool TryQueueWalkWarmup(WalkSession session, string reason)
    {
        if (_phase15Options.Enabled
            && _phase15Options.CorridorEnabled
            && _phase15Options.EvidencePrefetchEnabled
            && reason.Equals("location", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (session.Status is WalkSessionStatus.Completed or WalkSessionStatus.Cancelled)
        {
            return false;
        }

        var location = session.LastKnownLocation ?? session.StartingLocation;
        var nextStop = session.NextStop;
        var key = WarmupKey(session.WalkSessionId, session.RouteRevision, location, nextStop?.StopId, reason);
        lock (_gate)
        {
            if (_queuedKeys.Contains(key))
            {
                return false;
            }

            _queuedKeys.Add(key);
        }

        var request = new WalkWarmupRequest(
            key,
            $"walk warmup {reason}",
            session.WalkSessionId,
            session.RouteRevision,
            location,
            session.Interests.ToArray(),
            session.Route.Coordinates.ToArray(),
            nextStop?.StopId,
            nextStop?.Narration);

        if (!_queue.Writer.TryWrite(request))
        {
            lock (_gate)
            {
                _queuedKeys.Remove(key);
            }

            return false;
        }

        Interlocked.Increment(ref _enqueuedCount);
        return true;
    }

    public RoverBackgroundWorkStats GetStats()
    {
        lock (_gate)
        {
            return new RoverBackgroundWorkStats(
                _queuedKeys.Count,
                Interlocked.Read(ref _enqueuedCount),
                Interlocked.Read(ref _completedCount),
                Interlocked.Read(ref _failedCount),
                _lastWorkName,
                _lastWorkMilliseconds,
                _lastFailure);
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var request in _queue.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                await ProcessAsync(request, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            finally
            {
                lock (_gate)
                {
                    _queuedKeys.Remove(request.Key);
                }
            }
        }
    }

    private async Task ProcessAsync(WalkWarmupRequest request, CancellationToken stoppingToken)
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var services = scope.ServiceProvider;
            await WarmLocationContextAsync(services, request, stoppingToken);
            await WarmAdaptiveRouteStoriesAsync(services, request, stoppingToken);
            await WarmLocalDiscoveryAsync(services, request, stoppingToken);
            await WarmSpeechAsync(services, request, stoppingToken);
            stopwatch.Stop();
            Interlocked.Increment(ref _completedCount);
            RecordLast(request.Name, stopwatch.ElapsedMilliseconds, null);
            services.GetService<IBetaDiagnosticsService>()?.RecordOperation(request.Name, stopwatch.ElapsedMilliseconds, true);
        }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            stopwatch.Stop();
            Interlocked.Increment(ref _failedCount);
            var safeMessage = RedactionService.Redact(exception.Message);
            RecordLast(request.Name, stopwatch.ElapsedMilliseconds, safeMessage);
            _logger.LogDebug(exception, "Rover background warmup failed.");
        }
    }

    private Task WarmAdaptiveRouteStoriesAsync(
        IServiceProvider services,
        WalkWarmupRequest request,
        CancellationToken cancellationToken)
    {
        if (!_phase16Options.Enabled
            || request.Name is not ("walk warmup created" or "walk warmup adapted"))
        {
            return Task.CompletedTask;
        }

        return services.GetRequiredService<IAdaptiveRouteStoryPackService>().GenerateAsync(
            request.WalkSessionId,
            new GenerateAdaptiveRouteStoryPackCommand(null, "GeneralTraveller", "en", false),
            cancellationToken);
    }

    private static Task WarmLocationContextAsync(IServiceProvider services, WalkWarmupRequest request, CancellationToken cancellationToken)
    {
        var locationContext = services.GetRequiredService<ILocationStoryContextService>();
        return locationContext.GetContextAsync(
            new LocationContextQuery(
                request.Location,
                LocationContextRadiusMeters,
                request.WalkSessionId,
                null,
                request.RouteGeometry,
                request.Interests),
            cancellationToken);
    }

    private static Task WarmLocalDiscoveryAsync(IServiceProvider services, WalkWarmupRequest request, CancellationToken cancellationToken)
    {
        var localDiscovery = services.GetRequiredService<ILocalDiscoveryProvider>();
        return localDiscovery.FindCandidateStopsAsync(
            new CreateWalkCommand(
                request.Location,
                30,
                request.Interests.Count == 0
                    ? new[] { "coffee", "tea", "cakes", "burgers", "interesting sites" }
                    : request.Interests,
                WalkingPace.Standard,
                Array.Empty<AccessibilityPreference>()),
            cancellationToken,
            maximumStops: 12);
    }

    private static async Task WarmSpeechAsync(IServiceProvider services, WalkWarmupRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.NextStopNarration))
        {
            return;
        }

        var speech = services.GetRequiredService<IRoverSpeechService>();
        await speech.RenderAsync(
            new RenderSpeechCommand(
                Guid.Empty,
                request.NextStopNarration,
                SpeechPurpose.StopNarration,
                "en-US",
                request.WalkSessionId,
                request.NextStopId,
                $"warmup-{request.Key}"),
            Guid.NewGuid().ToString("n"),
            cancellationToken);
    }

    private void RecordLast(string name, long elapsedMilliseconds, string? failure)
    {
        lock (_gate)
        {
            _lastWorkName = RedactionService.Redact(name);
            _lastWorkMilliseconds = Math.Max(0, elapsedMilliseconds);
            _lastFailure = failure;
        }
    }

    private static string WarmupKey(string walkSessionId, int routeRevision, GeoLocation location, string? nextStopId, string reason)
    {
        return string.Join(
            ':',
            walkSessionId,
            routeRevision,
            Math.Round(location.Latitude, 3).ToString("F3"),
            Math.Round(location.Longitude, 3).ToString("F3"),
            nextStopId ?? "none",
            reason);
    }

    private sealed record WalkWarmupRequest(
        string Key,
        string Name,
        string WalkSessionId,
        int RouteRevision,
        GeoLocation Location,
        IReadOnlyCollection<string> Interests,
        IReadOnlyList<GeoLocation> RouteGeometry,
        string? NextStopId,
        string? NextStopNarration);
}
