using System.Threading;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Rover.Application.Beta;
using Rover.Application.Performance;
using Rover.Application.Speech;

namespace Rover.Infrastructure.Beta;

public sealed class InMemoryBetaDiagnosticsService : IBetaDiagnosticsService
{
    private const int MaximumSlowOperations = 8;
    private const long SlowOperationThresholdMilliseconds = 750;
    private readonly IConfiguration _configuration;
    private readonly IHostEnvironment _environment;
    private readonly ElevenLabsSpeechOptions _speechOptions;
    private readonly IRoverWalkPrefetchService? _prefetchService;
    private readonly object _operationLock = new();
    private readonly Queue<string> _slowOperations = new();
    private long _apiRequestCount;
    private long _locationUpdateCount;
    private long _routeRecalculationCount;
    private long _downloadedAudioBytes;
    private long _speechCacheHits;
    private long _speechCacheMisses;
    private string? _lastOperationName;
    private long? _lastOperationMilliseconds;
    private string? _lastSlowOperationName;
    private long? _lastSlowOperationMilliseconds;
    private DateTimeOffset? _lastSynchronizationUtc;
    private string? _lastSafeErrorCode;

    public InMemoryBetaDiagnosticsService(
        IConfiguration configuration,
        IHostEnvironment environment,
        ElevenLabsSpeechOptions speechOptions,
        IRoverWalkPrefetchService? prefetchService = null)
    {
        _configuration = configuration;
        _environment = environment;
        _speechOptions = speechOptions;
        _prefetchService = prefetchService;
    }

    public BetaDiagnosticsReport GetReport()
    {
        var background = _prefetchService?.GetStats()
            ?? new RoverBackgroundWorkStats(0, 0, 0, 0, null, null, null);
        return new BetaDiagnosticsReport(
            _configuration["Rover:Build:Version"] ?? "1.0.0",
            _configuration["Rover:Build:Number"] ?? "1",
            _environment.EnvironmentName,
            "Healthy",
            !string.IsNullOrWhiteSpace(
                Environment.GetEnvironmentVariable("GOOGLE_ROUTES_API_KEY")
                ?? Environment.GetEnvironmentVariable("GOOGLE_PLACES_API_KEY")
                ?? _configuration["Rover:Routing:Google:ApiKey"]),
            _speechOptions.Enabled,
            _speechOptions.Enabled
                && !string.IsNullOrWhiteSpace(_speechOptions.ApiKey)
                && !string.IsNullOrWhiteSpace(_speechOptions.VoiceId)
                && !string.IsNullOrWhiteSpace(_speechOptions.ModelId),
            Environment.GetEnvironmentVariable("ROVER_STORAGE_MODE") ?? _configuration["Rover:Storage:Mode"] ?? "InMemory",
            Environment.GetEnvironmentVariable("ROVER_ROUTING_MODE") ?? _configuration["Rover:Routing:Mode"] ?? "Mock",
            Environment.GetEnvironmentVariable("ROVER_DISCOVERY_MODE") ?? _configuration["Rover:Discovery:Mode"] ?? "Mock",
            Environment.GetEnvironmentVariable("ROVER_LOCAL_DISCOVERY_MODE") ?? _configuration["Rover:LocalDiscovery:Mode"] ?? "None",
            Environment.GetEnvironmentVariable("ROVER_CONVERSATION_MODE") ?? _configuration["Rover:Conversation:Mode"] ?? "Mock",
            Interlocked.Read(ref _apiRequestCount),
            Interlocked.Read(ref _locationUpdateCount),
            Interlocked.Read(ref _routeRecalculationCount),
            Interlocked.Read(ref _downloadedAudioBytes),
            Interlocked.Read(ref _speechCacheHits),
            Interlocked.Read(ref _speechCacheMisses),
            _lastOperationName,
            _lastOperationMilliseconds,
            _lastSlowOperationName,
            _lastSlowOperationMilliseconds,
            _slowOperations.ToArray(),
            background.PendingCount,
            background.EnqueuedCount,
            background.CompletedCount,
            background.FailedCount,
            background.LastWorkName,
            background.LastWorkMilliseconds,
            background.LastFailure,
            _lastSynchronizationUtc,
            _lastSafeErrorCode);
    }

    public void RecordApiRequest() => Interlocked.Increment(ref _apiRequestCount);
    public void RecordLocationUpdate() => Interlocked.Increment(ref _locationUpdateCount);
    public void RecordRouteRecalculation() => Interlocked.Increment(ref _routeRecalculationCount);
    public void RecordAudioDownload(long bytes, bool cacheHit)
    {
        Interlocked.Add(ref _downloadedAudioBytes, Math.Max(0, bytes));
        if (cacheHit)
        {
            Interlocked.Increment(ref _speechCacheHits);
        }
        else
        {
            Interlocked.Increment(ref _speechCacheMisses);
        }
    }

    public void RecordOperation(string name, long elapsedMilliseconds, bool success)
    {
        var safeName = RedactionService.Redact(name);
        var elapsed = Math.Max(0, elapsedMilliseconds);
        lock (_operationLock)
        {
            _lastOperationName = safeName;
            _lastOperationMilliseconds = elapsed;
            if (elapsed < SlowOperationThresholdMilliseconds)
            {
                return;
            }

            _lastSlowOperationName = safeName;
            _lastSlowOperationMilliseconds = elapsed;
            _slowOperations.Enqueue($"{safeName}: {elapsed} ms, {(success ? "ok" : "failed")}");
            while (_slowOperations.Count > MaximumSlowOperations)
            {
                _slowOperations.Dequeue();
            }
        }
    }

    public void RecordSynchronization(DateTimeOffset synchronizedAtUtc) => _lastSynchronizationUtc = synchronizedAtUtc;
    public void RecordSafeError(string safeErrorCode) => _lastSafeErrorCode = RedactionService.Redact(safeErrorCode);
}
