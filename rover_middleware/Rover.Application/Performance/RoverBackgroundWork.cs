using Rover.Domain.Walks;

namespace Rover.Application.Performance;

public interface IRoverWalkPrefetchService
{
    bool TryQueueWalkWarmup(WalkSession session, string reason);
    RoverBackgroundWorkStats GetStats();
}

public sealed record RoverBackgroundWorkStats(
    int PendingCount,
    long EnqueuedCount,
    long CompletedCount,
    long FailedCount,
    string? LastWorkName,
    long? LastWorkMilliseconds,
    string? LastFailure);
