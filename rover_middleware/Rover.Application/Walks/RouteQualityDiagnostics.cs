using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public sealed record RouteQualityDiagnostics(
    int TotalRouteDistanceMeters,
    int EstimatedWalkingTimeMinutes,
    int EstimatedStopTimeMinutes,
    int EstimatedExperienceTimeMinutes,
    double AvailableTimeUtilization,
    int BacktrackingEstimateMeters,
    int RepeatedSegmentCount,
    int ReturnToStartEstimateMeters,
    IReadOnlyList<string> Warnings);

public interface IRouteQualityAnalyzer
{
    RouteQualityDiagnostics Analyze(WalkSession session);
}

public sealed class DeterministicRouteQualityAnalyzer : IRouteQualityAnalyzer
{
    public RouteQualityDiagnostics Analyze(WalkSession session)
    {
        var walkingMinutes = Math.Max(0, session.Route.DurationMinutes);
        var stopMinutes = session.Stops.Sum(stop => Math.Max(0, stop.EstimatedVisitMinutes));
        var experienceMinutes = walkingMinutes + stopMinutes;
        var utilization = session.AvailableMinutes <= 0
            ? 0
            : Math.Round((double)experienceMinutes / session.AvailableMinutes, 2);
        var backtrackingMeters = EstimateBacktrackingMeters(session.Stops);
        var repeatedSegments = CountRepeatedSegments(session.Route.Coordinates);
        var returnToStartMeters = session.Stops.Count == 0
            ? 0
            : (int)Math.Round(RouteMath.DistanceMeters(session.Stops[^1].Location, session.StartingLocation));

        var warnings = new List<string>();
        if (utilization < 0.65)
        {
            warnings.Add("Route uses less than 65% of the requested walk time.");
        }

        if (utilization > 1.15)
        {
            warnings.Add("Route is likely longer than the requested walk time.");
        }

        if (backtrackingMeters > Math.Max(150, session.Route.DistanceMeters * 0.25))
        {
            warnings.Add("Route appears to double back more than expected.");
        }

        if (repeatedSegments > 0)
        {
            warnings.Add("Route contains repeated nearby segments.");
        }

        if (returnToStartMeters > Math.Max(500, session.Route.DistanceMeters * 0.35))
        {
            warnings.Add("Final stop may leave the user far from the starting point.");
        }

        return new RouteQualityDiagnostics(
            Math.Max(0, session.Route.DistanceMeters),
            walkingMinutes,
            stopMinutes,
            experienceMinutes,
            utilization,
            backtrackingMeters,
            repeatedSegments,
            returnToStartMeters,
            warnings);
    }

    private static int EstimateBacktrackingMeters(IReadOnlyList<WalkStop> stops)
    {
        if (stops.Count < 3)
        {
            return 0;
        }

        var excessMeters = 0d;
        for (var i = 1; i < stops.Count - 1; i++)
        {
            var previous = stops[i - 1].Location;
            var current = stops[i].Location;
            var next = stops[i + 1].Location;
            var routed = RouteMath.DistanceMeters(previous, current) + RouteMath.DistanceMeters(current, next);
            var direct = RouteMath.DistanceMeters(previous, next);
            if (direct > 0 && routed / direct >= 1.8)
            {
                excessMeters += routed - direct;
            }
        }

        return (int)Math.Round(excessMeters);
    }

    private static int CountRepeatedSegments(IReadOnlyList<GeoLocation> coordinates)
    {
        if (coordinates.Count < 4)
        {
            return 0;
        }

        var seen = new HashSet<string>(StringComparer.Ordinal);
        var repeated = 0;
        for (var i = 1; i < coordinates.Count; i++)
        {
            var a = SegmentKey(coordinates[i - 1]);
            var b = SegmentKey(coordinates[i]);
            var key = string.CompareOrdinal(a, b) <= 0 ? $"{a}>{b}" : $"{b}>{a}";
            if (!seen.Add(key))
            {
                repeated++;
            }
        }

        return repeated;
    }

    private static string SegmentKey(GeoLocation point)
    {
        return $"{Math.Round(point.Latitude, 4):F4},{Math.Round(point.Longitude, 4):F4}";
    }
}
