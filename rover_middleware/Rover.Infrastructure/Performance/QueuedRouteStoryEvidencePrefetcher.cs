using System.Diagnostics;
using System.Threading.Channels;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Rover.Application.Beta;
using Rover.Application.Journeys;
using Rover.Application.LocationIntelligence;

namespace Rover.Infrastructure.Performance;

public sealed class QueuedRouteStoryEvidencePrefetcher : BackgroundService, IRouteStoryEvidencePrefetcher
{
    private const int MaximumRememberedCompletedKeys = 512;
    private readonly Channel<RouteStoryEvidencePrefetchRequest> _queue;
    private readonly HashSet<string> _pendingKeys = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _completedKeys = new(StringComparer.OrdinalIgnoreCase);
    private readonly Queue<string> _completedKeyOrder = new();
    private readonly Dictionary<string, int> _latestRouteRevisions = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gate = new();
    private readonly Phase15Options _options;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<QueuedRouteStoryEvidencePrefetcher> _logger;
    private long _enqueuedCount;
    private long _completedCount;
    private long _failedCount;
    private long _staleDiscardedCount;
    private string? _lastSegmentId;
    private long? _lastElapsedMilliseconds;
    private string? _lastFailure;

    public QueuedRouteStoryEvidencePrefetcher(
        Phase15Options options,
        IServiceScopeFactory scopeFactory,
        ILogger<QueuedRouteStoryEvidencePrefetcher> logger)
    {
        _options = options;
        _scopeFactory = scopeFactory;
        _logger = logger;
        _queue = Channel.CreateBounded<RouteStoryEvidencePrefetchRequest>(
            new BoundedChannelOptions(Math.Clamp(options.PrefetchQueueCapacity, 1, 128))
            {
                FullMode = BoundedChannelFullMode.Wait,
                SingleReader = true,
                SingleWriter = false
            });
    }

    public bool TryQueue(
        RouteStoryPlan plan,
        IReadOnlyList<Rover.Domain.Walks.GeoLocation> routeGeometry,
        IReadOnlyCollection<string> interests,
        int startSequenceNumber,
        string reason)
    {
        if (!_options.Enabled || !_options.CorridorEnabled || !_options.EvidencePrefetchEnabled)
        {
            return false;
        }

        var queuedAny = false;
        lock (_gate)
        {
            if (_latestRouteRevisions.TryGetValue(plan.WalkSessionId, out var latestRevision)
                && plan.RouteRevision < latestRevision)
            {
                return false;
            }

            _latestRouteRevisions[plan.WalkSessionId] = plan.RouteRevision;
            foreach (var segment in RouteStoryPrefetchBatchPlanner.Select(
                         plan,
                         startSequenceNumber,
                         _options.PrefetchSegmentCount))
            {
                var key = $"{plan.WalkSessionId}:r{plan.RouteRevision}:s{segment.SequenceNumber}";
                if (_pendingKeys.Contains(key) || _completedKeys.Contains(key))
                {
                    continue;
                }

                var request = new RouteStoryEvidencePrefetchRequest(
                    key,
                    plan.WalkSessionId,
                    plan.RouteId,
                    plan.RouteRevision,
                    segment,
                    routeGeometry.ToArray(),
                    interests.ToArray(),
                    reason);
                if (!_queue.Writer.TryWrite(request))
                {
                    continue;
                }

                _pendingKeys.Add(key);
                Interlocked.Increment(ref _enqueuedCount);
                queuedAny = true;
            }
        }

        return queuedAny;
    }

    public RouteStoryEvidencePrefetchStats GetStats()
    {
        lock (_gate)
        {
            return new RouteStoryEvidencePrefetchStats(
                _pendingKeys.Count,
                _completedKeys.Count,
                Interlocked.Read(ref _enqueuedCount),
                Interlocked.Read(ref _completedCount),
                Interlocked.Read(ref _failedCount),
                Interlocked.Read(ref _staleDiscardedCount),
                _lastSegmentId,
                _lastElapsedMilliseconds,
                _lastFailure);
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var request in _queue.Reader.ReadAllAsync(stoppingToken))
        {
            if (IsStale(request))
            {
                Complete(request, null, stale: true);
                continue;
            }

            var stopwatch = Stopwatch.StartNew();
            try
            {
                using var scope = _scopeFactory.CreateScope();
                var locationContext = scope.ServiceProvider.GetRequiredService<ILocationStoryContextService>();
                await locationContext.GetContextAsync(
                    new LocationContextQuery(
                        request.Segment.Anchor,
                        request.Segment.Opportunities.FirstOrDefault()?.CorridorRadiusMeters
                            ?? _options.CorridorRadiusMeters,
                        $"{request.WalkSessionId}:r{request.RouteRevision}",
                        null,
                        request.RouteGeometry,
                        request.Interests),
                    stoppingToken);
                stopwatch.Stop();

                if (IsStale(request))
                {
                    Complete(request, stopwatch.ElapsedMilliseconds, stale: true);
                    continue;
                }

                Interlocked.Increment(ref _completedCount);
                Complete(request, stopwatch.ElapsedMilliseconds, stale: false);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception exception)
            {
                stopwatch.Stop();
                Interlocked.Increment(ref _failedCount);
                var safeFailure = RedactionService.Redact(exception.Message);
                Complete(request, stopwatch.ElapsedMilliseconds, stale: false, safeFailure);
                _logger.LogDebug(exception, "Route story evidence prefetch failed for {SegmentId}.", request.Segment.SegmentId);
            }
        }
    }

    private bool IsStale(RouteStoryEvidencePrefetchRequest request)
    {
        lock (_gate)
        {
            return _latestRouteRevisions.TryGetValue(request.WalkSessionId, out var latestRevision)
                && latestRevision != request.RouteRevision;
        }
    }

    private void Complete(
        RouteStoryEvidencePrefetchRequest request,
        long? elapsedMilliseconds,
        bool stale,
        string? failure = null)
    {
        lock (_gate)
        {
            _pendingKeys.Remove(request.Key);
            _lastSegmentId = request.Segment.SegmentId;
            _lastElapsedMilliseconds = elapsedMilliseconds;
            _lastFailure = failure;
            if (stale)
            {
                Interlocked.Increment(ref _staleDiscardedCount);
                return;
            }

            if (failure is null && _completedKeys.Add(request.Key))
            {
                _completedKeyOrder.Enqueue(request.Key);
                while (_completedKeyOrder.Count > MaximumRememberedCompletedKeys)
                {
                    _completedKeys.Remove(_completedKeyOrder.Dequeue());
                }
            }
        }
    }
}
