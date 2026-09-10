using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public sealed record StopLifecycleConsistencyReport(
    bool IsConsistent,
    int StopCount,
    int RouteRevision,
    string? NextStopId,
    IReadOnlyList<string> Warnings);

public interface IStopLifecycleConsistencyService
{
    StopLifecycleConsistencyReport Inspect(WalkSession session);
    StopLifecycleConsistencyReport RepairRecoverable(WalkSession session, DateTimeOffset repairedAtUtc);
}

public sealed class StopLifecycleConsistencyService : IStopLifecycleConsistencyService
{
    public StopLifecycleConsistencyReport RepairRecoverable(WalkSession session, DateTimeOffset repairedAtUtc)
    {
        var repairs = session.RepairRecoverableLifecycle(repairedAtUtc);
        var report = Inspect(session);
        if (repairs.Count == 0)
        {
            return report;
        }

        return report with
        {
            Warnings = repairs.Concat(report.Warnings).ToArray()
        };
    }

    public StopLifecycleConsistencyReport Inspect(WalkSession session)
    {
        var warnings = new List<string>();
        var stops = session.Stops;
        var stopIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        for (var i = 0; i < stops.Count; i++)
        {
            var expectedSequence = i + 1;
            var stop = stops[i];
            if (stop.SequenceNumber != expectedSequence)
            {
                warnings.Add($"Stop sequence is not consecutive at position {expectedSequence}.");
            }

            if (!stopIds.Add(stop.StopId))
            {
                warnings.Add($"Stop id '{stop.StopId}' appears more than once.");
            }

            if (stop.ArrivalRadiusMeters <= 0)
            {
                warnings.Add($"Stop '{stop.StopId}' has no usable arrival radius.");
            }
        }

        var nextStop = session.NextStop;
        var visitedBeforeNext = stops.TakeWhile(stop => stop.Visited).Count();
        if (nextStop is not null && stops.ElementAtOrDefault(visitedBeforeNext)?.StopId != nextStop.StopId)
        {
            warnings.Add("Next stop does not match the first unvisited ordered stop.");
        }

        if (session.Route.Coordinates.Count < 2)
        {
            warnings.Add("Route has too few coordinates to render or evaluate.");
        }

        var latestRevision = session.RouteRevisions.MaxBy(revision => revision.Revision);
        if (latestRevision is null || latestRevision.Revision != session.RouteRevision)
        {
            warnings.Add("Route revision history does not match the active route revision.");
        }

        return new StopLifecycleConsistencyReport(
            warnings.Count == 0,
            stops.Count,
            session.RouteRevision,
            nextStop?.StopId,
            warnings);
    }
}
