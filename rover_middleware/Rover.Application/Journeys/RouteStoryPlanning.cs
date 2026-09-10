using System.Collections.Concurrent;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Journeys;

public sealed class Phase15Options
{
    public bool Enabled { get; set; }
    public bool CorridorEnabled { get; set; }
    public bool EvidencePrefetchEnabled { get; set; }
    public bool StoryPackV2Enabled { get; set; }
    public bool HistoricalRetrievalEnabled { get; set; }
    public bool LiveWeatherEnabled { get; set; }
    public bool EventsEnabled { get; set; }
    public bool CurrentInfoEnabled { get; set; }
    public bool NarrativeArcEnabled { get; set; }
    public bool NarrativeSchedulerEnabled { get; set; }
    public bool InteractionMemoryEnabled { get; set; }
    public int TargetSegmentSeconds { get; set; } = 180;
    public int MinimumSegmentMeters { get; set; } = 80;
    public int MaximumSegmentMeters { get; set; } = 350;
    public int CorridorRadiusMeters { get; set; } = 175;
    public int MinimumNavigationGapSeconds { get; set; } = 30;
    public int PrefetchSegmentCount { get; set; } = 3;
    public int PrefetchQueueCapacity { get; set; } = 24;
    public int UrgentManeuverWindowSeconds { get; set; } = 35;
    public int StoryNavigationBufferSeconds { get; set; } = 12;
    public int InteractionRetentionDays { get; set; } = 90;
    public int MaximumInteractionEventsPerProfile { get; set; } = 200;
    public int CompletedStoryWeight { get; set; } = 1;
    public int SkippedStoryWeight { get; set; } = -2;
    public int ReplayedStoryWeight { get; set; } = 2;
    public int TellMoreStoryWeight { get; set; } = 3;
    public int DismissedStoryWeight { get; set; } = -3;
}

public enum RouteStoryTravelMode
{
    Walking
}

public enum RouteRelativeDirection
{
    Ahead,
    Behind,
    Left,
    Right,
    AlongRoute
}

public enum StoryOpportunityKind
{
    CorridorSearch
}

public sealed record StoryTriggerWindow(
    double OpensAtRouteMeters,
    double ClosesAtRouteMeters,
    int MinimumNavigationGapSeconds,
    bool NavigationSensitive);

public sealed record StoryCandidate(
    string CandidateId,
    string EntityId,
    GeoLocation Location,
    RouteRelativeDirection Direction,
    IReadOnlyList<string> Categories,
    IReadOnlyList<string> EvidenceIds);

public sealed record StoryOpportunity(
    string OpportunityId,
    StoryOpportunityKind Kind,
    GeoLocation Anchor,
    int CorridorRadiusMeters,
    RouteRelativeDirection Direction,
    IReadOnlyList<string> SearchCategories,
    IReadOnlyList<StoryCandidate> Candidates,
    StoryTriggerWindow TriggerWindow);

public sealed record RouteStorySegment(
    string SegmentId,
    int SequenceNumber,
    GeoLocation Start,
    GeoLocation End,
    GeoLocation Anchor,
    double StartRouteMeters,
    double EndRouteMeters,
    int DistanceMeters,
    int EstimatedDurationSeconds,
    bool ContainsNavigationManeuver,
    IReadOnlyList<StoryOpportunity> Opportunities);

public sealed record RouteStoryPlan(
    string WalkSessionId,
    string RouteId,
    int RouteRevision,
    RouteStoryTravelMode TravelMode,
    DateTimeOffset GeneratedUtc,
    IReadOnlyList<RouteStorySegment> Segments);

public interface IRouteStoryPlanner
{
    RouteStoryPlan CreatePlan(WalkSession session, DateTimeOffset generatedUtc);
}

public interface IRouteStoryPlanRepository
{
    Task<RouteStoryPlan?> GetAsync(string walkSessionId, int routeRevision, CancellationToken cancellationToken);
    Task StoreAsync(RouteStoryPlan plan, CancellationToken cancellationToken);
}

public interface IRouteStoryPlanService
{
    Task<RouteStoryPlan?> RefreshAsync(WalkSession session, CancellationToken cancellationToken);
    Task<bool> PrefetchUpcomingAsync(WalkSession session, string reason, CancellationToken cancellationToken);
    Task<RouteStoryPlan?> GetAsync(string walkSessionId, int routeRevision, CancellationToken cancellationToken);
}

public sealed record RouteStoryEvidencePrefetchRequest(
    string Key,
    string WalkSessionId,
    string RouteId,
    int RouteRevision,
    RouteStorySegment Segment,
    IReadOnlyList<GeoLocation> RouteGeometry,
    IReadOnlyCollection<string> Interests,
    string Reason);

public sealed record RouteStoryEvidencePrefetchStats(
    int PendingCount,
    int CompletedKeyCount,
    long EnqueuedCount,
    long CompletedCount,
    long FailedCount,
    long StaleDiscardedCount,
    string? LastSegmentId,
    long? LastElapsedMilliseconds,
    string? LastFailure);

public interface IRouteStoryEvidencePrefetcher
{
    bool TryQueue(
        RouteStoryPlan plan,
        IReadOnlyList<GeoLocation> routeGeometry,
        IReadOnlyCollection<string> interests,
        int startSequenceNumber,
        string reason);

    RouteStoryEvidencePrefetchStats GetStats();
}

public static class RouteStoryPrefetchBatchPlanner
{
    public static IReadOnlyList<RouteStorySegment> Select(
        RouteStoryPlan plan,
        int startSequenceNumber,
        int maximumSegments)
    {
        var start = Math.Max(1, startSequenceNumber);
        return plan.Segments
            .Where(segment => segment.SequenceNumber >= start)
            .OrderBy(segment => segment.SequenceNumber)
            .Take(Math.Clamp(maximumSegments, 1, 12))
            .ToArray();
    }
}

public interface IRouteDirectionClassifier
{
    RouteRelativeDirection Classify(GeoLocation routeStart, GeoLocation routeEnd, GeoLocation observer, GeoLocation candidate);
}

public sealed class InMemoryRouteStoryPlanRepository : IRouteStoryPlanRepository
{
    private readonly ConcurrentDictionary<string, RouteStoryPlan> _plans = new(StringComparer.OrdinalIgnoreCase);

    public Task<RouteStoryPlan?> GetAsync(string walkSessionId, int routeRevision, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _plans.TryGetValue(Key(walkSessionId, routeRevision), out var plan);
        return Task.FromResult(plan);
    }

    public Task StoreAsync(RouteStoryPlan plan, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _plans[Key(plan.WalkSessionId, plan.RouteRevision)] = plan;
        return Task.CompletedTask;
    }

    private static string Key(string walkSessionId, int routeRevision) => $"{walkSessionId}:{routeRevision}";
}

public sealed class RouteStoryPlanService : IRouteStoryPlanService
{
    private readonly Phase15Options _options;
    private readonly IRouteStoryPlanner _planner;
    private readonly IRouteStoryPlanRepository _repository;
    private readonly TimeProvider _timeProvider;
    private readonly IRouteStoryEvidencePrefetcher? _evidencePrefetcher;

    public RouteStoryPlanService(
        Phase15Options options,
        IRouteStoryPlanner planner,
        IRouteStoryPlanRepository repository,
        TimeProvider timeProvider,
        IRouteStoryEvidencePrefetcher? evidencePrefetcher = null)
    {
        _options = options;
        _planner = planner;
        _repository = repository;
        _timeProvider = timeProvider;
        _evidencePrefetcher = evidencePrefetcher;
    }

    public async Task<RouteStoryPlan?> RefreshAsync(WalkSession session, CancellationToken cancellationToken)
    {
        if (!_options.Enabled || !_options.CorridorEnabled)
        {
            return null;
        }

        var plan = _planner.CreatePlan(session, _timeProvider.GetUtcNow());
        await _repository.StoreAsync(plan, cancellationToken);
        QueueEvidence(plan, session, 1, "route-planned");
        return plan;
    }

    public async Task<bool> PrefetchUpcomingAsync(
        WalkSession session,
        string reason,
        CancellationToken cancellationToken)
    {
        if (!PrefetchEnabled)
        {
            return false;
        }

        var plan = await _repository.GetAsync(session.WalkSessionId, session.RouteRevision, cancellationToken);
        if (plan is null)
        {
            return false;
        }

        var current = session.LastKnownLocation ?? session.StartingLocation;
        var progress = RouteMath.ProgressPercentage(current, session.Route);
        var routeMeters = plan.Segments.Count == 0
            ? 0
            : plan.Segments[^1].EndRouteMeters * progress / 100d;
        var currentSegment = plan.Segments.FirstOrDefault(segment =>
                routeMeters <= segment.EndRouteMeters)
            ?? plan.Segments.LastOrDefault();
        return currentSegment is not null
            && QueueEvidence(plan, session, currentSegment.SequenceNumber, reason);
    }

    public Task<RouteStoryPlan?> GetAsync(string walkSessionId, int routeRevision, CancellationToken cancellationToken) =>
        _repository.GetAsync(walkSessionId, routeRevision, cancellationToken);

    private bool QueueEvidence(RouteStoryPlan plan, WalkSession session, int startSequenceNumber, string reason)
    {
        return PrefetchEnabled
            && _evidencePrefetcher!.TryQueue(
                plan,
                session.Route.Coordinates,
                session.Interests,
                startSequenceNumber,
                reason);
    }

    private bool PrefetchEnabled =>
        _options.Enabled
        && _options.CorridorEnabled
        && _options.EvidencePrefetchEnabled
        && _evidencePrefetcher is not null;
}

public sealed class DeterministicRouteDirectionClassifier : IRouteDirectionClassifier
{
    public RouteRelativeDirection Classify(
        GeoLocation routeStart,
        GeoLocation routeEnd,
        GeoLocation observer,
        GeoLocation candidate)
    {
        var routeBearing = Bearing(routeStart, routeEnd);
        var candidateBearing = Bearing(observer, candidate);
        var difference = NormalizeBearing(candidateBearing - routeBearing);
        var absolute = Math.Abs(difference);

        if (absolute <= 45)
        {
            return RouteRelativeDirection.Ahead;
        }

        if (absolute >= 135)
        {
            return RouteRelativeDirection.Behind;
        }

        return difference > 0
            ? RouteRelativeDirection.Right
            : RouteRelativeDirection.Left;
    }

    private static double Bearing(GeoLocation from, GeoLocation to)
    {
        var fromLatitude = DegreesToRadians(from.Latitude);
        var toLatitude = DegreesToRadians(to.Latitude);
        var longitudeDelta = DegreesToRadians(to.Longitude - from.Longitude);
        var y = Math.Sin(longitudeDelta) * Math.Cos(toLatitude);
        var x = Math.Cos(fromLatitude) * Math.Sin(toLatitude)
            - Math.Sin(fromLatitude) * Math.Cos(toLatitude) * Math.Cos(longitudeDelta);
        return RadiansToDegrees(Math.Atan2(y, x));
    }

    private static double NormalizeBearing(double value)
    {
        var normalized = (value + 540) % 360 - 180;
        return normalized == -180 ? 180 : normalized;
    }

    private static double DegreesToRadians(double value) => value * Math.PI / 180;
    private static double RadiansToDegrees(double value) => value * 180 / Math.PI;
}

public sealed class DeterministicRouteStoryPlanner : IRouteStoryPlanner
{
    private static readonly string[] DefaultSearchCategories =
    [
        "history",
        "architecture",
        "culture",
        "nature",
        "notable people",
        "food history",
        "film and television"
    ];

    private readonly Phase15Options _options;

    public DeterministicRouteStoryPlanner(Phase15Options options)
    {
        _options = options;
    }

    public RouteStoryPlan CreatePlan(WalkSession session, DateTimeOffset generatedUtc)
    {
        var route = session.Route;
        if (route.Coordinates.Count < 2)
        {
            throw new InvalidOperationException("A route story plan requires at least two route coordinates.");
        }

        var totalDistance = GeometryDistance(route.Coordinates);
        var walkingSpeed = WalkingSpeedMetersPerSecond(session.WalkingPace);
        var minimumSegmentMeters = Math.Max(20, _options.MinimumSegmentMeters);
        var maximumSegmentMeters = Math.Max(minimumSegmentMeters, _options.MaximumSegmentMeters);
        var targetDistance = Math.Clamp(
            walkingSpeed * Math.Max(30, _options.TargetSegmentSeconds),
            minimumSegmentMeters,
            maximumSegmentMeters);
        var segmentCount = Math.Max(1, (int)Math.Ceiling(totalDistance / targetDistance));
        var categories = session.Interests
            .Concat(DefaultSearchCategories)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim().ToLowerInvariant())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var segments = new List<RouteStorySegment>(segmentCount);

        for (var index = 0; index < segmentCount; index++)
        {
            var startDistance = totalDistance * index / segmentCount;
            var endDistance = totalDistance * (index + 1) / segmentCount;
            var segmentDistance = Math.Max(1, (int)Math.Round(endDistance - startDistance));
            var start = PointAtDistance(route.Coordinates, startDistance);
            var end = PointAtDistance(route.Coordinates, endDistance);
            var anchor = PointAtDistance(route.Coordinates, (startDistance + endDistance) / 2);
            var containsManeuver = route.Maneuvers.Any(maneuver =>
                maneuver.Location is not null
                && DistanceFromRouteSliceMeters(maneuver.Location, route.Coordinates, startDistance, endDistance) <= 25);
            var trigger = TriggerWindow(startDistance, endDistance, walkingSpeed, containsManeuver);
            var segmentId = $"{session.WalkSessionId}-r{session.RouteRevision}-s{index + 1}";
            var opportunity = new StoryOpportunity(
                $"{segmentId}-corridor",
                StoryOpportunityKind.CorridorSearch,
                anchor,
                Math.Clamp(_options.CorridorRadiusMeters, 50, 1000),
                RouteRelativeDirection.AlongRoute,
                categories,
                Array.Empty<StoryCandidate>(),
                trigger);

            segments.Add(new RouteStorySegment(
                segmentId,
                index + 1,
                start,
                end,
                anchor,
                startDistance,
                endDistance,
                segmentDistance,
                Math.Max(1, (int)Math.Round(segmentDistance / walkingSpeed)),
                containsManeuver,
                new[] { opportunity }));
        }

        return new RouteStoryPlan(
            session.WalkSessionId,
            route.RouteId,
            session.RouteRevision,
            RouteStoryTravelMode.Walking,
            generatedUtc,
            segments);
    }

    private StoryTriggerWindow TriggerWindow(
        double startDistance,
        double endDistance,
        double walkingSpeed,
        bool containsManeuver)
    {
        var length = Math.Max(0, endDistance - startDistance);
        var openingPadding = Math.Min(20, length * 0.15);
        var closingPadding = Math.Min(walkingSpeed * Math.Max(10, _options.MinimumNavigationGapSeconds), length * 0.25);
        var opens = startDistance + openingPadding;
        var closes = Math.Max(opens, endDistance - closingPadding);
        return new StoryTriggerWindow(
            opens,
            closes,
            Math.Max(10, _options.MinimumNavigationGapSeconds),
            containsManeuver);
    }

    private static double WalkingSpeedMetersPerSecond(WalkingPace pace) => pace switch
    {
        WalkingPace.Leisurely => 1.0,
        WalkingPace.Brisk => 1.7,
        _ => 1.35
    };

    private static double GeometryDistance(IReadOnlyList<GeoLocation> coordinates)
    {
        var distance = 0d;
        for (var index = 1; index < coordinates.Count; index++)
        {
            distance += RouteMath.DistanceMeters(coordinates[index - 1], coordinates[index]);
        }

        return distance;
    }

    private static GeoLocation PointAtDistance(IReadOnlyList<GeoLocation> coordinates, double targetDistance)
    {
        if (targetDistance <= 0)
        {
            return coordinates[0];
        }

        var traversed = 0d;
        for (var index = 1; index < coordinates.Count; index++)
        {
            var start = coordinates[index - 1];
            var end = coordinates[index];
            var edgeDistance = RouteMath.DistanceMeters(start, end);
            if (edgeDistance <= 0)
            {
                continue;
            }

            if (traversed + edgeDistance >= targetDistance)
            {
                var ratio = Math.Clamp((targetDistance - traversed) / edgeDistance, 0, 1);
                return new GeoLocation(
                    start.Latitude + (end.Latitude - start.Latitude) * ratio,
                    start.Longitude + (end.Longitude - start.Longitude) * ratio);
            }

            traversed += edgeDistance;
        }

        return coordinates[^1];
    }

    private static double DistanceFromRouteSliceMeters(
        GeoLocation location,
        IReadOnlyList<GeoLocation> coordinates,
        double startDistance,
        double endDistance)
    {
        var start = PointAtDistance(coordinates, startDistance);
        var anchor = PointAtDistance(coordinates, (startDistance + endDistance) / 2);
        var end = PointAtDistance(coordinates, endDistance);
        return Math.Min(
            RouteMath.DistanceToSegmentMeters(location, start, anchor),
            RouteMath.DistanceToSegmentMeters(location, anchor, end));
    }
}
