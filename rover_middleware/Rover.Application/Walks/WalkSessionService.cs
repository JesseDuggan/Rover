using Rover.Domain.Walks;
using Rover.Application.Journeys;

namespace Rover.Application.Walks;

public sealed class WalkSessionService : IWalkSessionService
{
    private readonly IWalkPlanner _walkPlanner;
    private readonly IWalkSessionRepository _repository;
    private readonly TimeProvider _timeProvider;
    private readonly LocationTrackingOptions _trackingOptions;
    private readonly IRouteStoryPlanService? _routeStoryPlans;
    private readonly IJourneyNarrativeArcService? _narrativeArcs;

    public WalkSessionService(
        IWalkPlanner walkPlanner,
        IWalkSessionRepository repository,
        TimeProvider timeProvider,
        LocationTrackingOptions? trackingOptions = null,
        IRouteStoryPlanService? routeStoryPlans = null,
        IJourneyNarrativeArcService? narrativeArcs = null)
    {
        _walkPlanner = walkPlanner;
        _repository = repository;
        _timeProvider = timeProvider;
        _trackingOptions = trackingOptions ?? new LocationTrackingOptions();
        _routeStoryPlans = routeStoryPlans;
        _narrativeArcs = narrativeArcs;
    }

    public async Task<WalkSession> CreateAsync(CreateWalkCommand command, CancellationToken cancellationToken)
    {
        var session = await _walkPlanner.PlanWalkAsync(command, cancellationToken);
        await _repository.AddAsync(session, cancellationToken);
        if (_routeStoryPlans is not null)
        {
            await _routeStoryPlans.RefreshAsync(session, cancellationToken);
        }
        if (_narrativeArcs is not null)
        {
            await _narrativeArcs.RefreshAsync(session, cancellationToken);
        }
        return session;
    }

    public Task<WalkSession?> GetAsync(string walkSessionId, CancellationToken cancellationToken)
    {
        return _repository.GetByIdAsync(walkSessionId, cancellationToken);
    }

    public async Task<IReadOnlyList<WalkStop>?> GetStopsAsync(string walkSessionId, CancellationToken cancellationToken)
    {
        var session = await _repository.GetByIdAsync(walkSessionId, cancellationToken);
        return session?.Stops;
    }

    public async Task<WalkStop?> GetNextStopAsync(string walkSessionId, CancellationToken cancellationToken)
    {
        var session = await _repository.GetByIdAsync(walkSessionId, cancellationToken);
        return session?.NextStop;
    }

    public async Task<WalkSession> StartAsync(string walkSessionId, CancellationToken cancellationToken)
    {
        var session = await GetRequiredAsync(walkSessionId, cancellationToken);
        session.Start(_timeProvider.GetUtcNow());
        await _repository.UpdateAsync(session, cancellationToken);
        if (_routeStoryPlans is not null)
        {
            await _routeStoryPlans.PrefetchUpcomingAsync(session, "walk-started", cancellationToken);
        }
        return session;
    }

    public async Task<LocationUpdateResult> UpdateLocationAsync(string walkSessionId, LocationUpdateCommand command, CancellationToken cancellationToken)
    {
        var session = await GetRequiredAsync(walkSessionId, cancellationToken);
        if (session.Status != WalkSessionStatus.InProgress)
        {
            throw new WalkLifecycleException("Location updates are accepted only while a walk is InProgress.");
        }

        var now = _timeProvider.GetUtcNow();
        if (command.RecordedAtUtc < now.AddSeconds(-_trackingOptions.StaleReadingSeconds))
        {
            throw new WalkLifecycleException("Location reading was too old to use for arrival or routing decisions.");
        }

        if (session.LastKnownLocation is not null && session.TrackingState.LastLocationRecordedAtUtc is not null)
        {
            var secondsSinceLast = Math.Max(1, Math.Abs((command.RecordedAtUtc - session.TrackingState.LastLocationRecordedAtUtc.Value).TotalSeconds));
            var jumpMeters = RouteMath.DistanceMeters(command.Location, session.LastKnownLocation);
            if (secondsSinceLast <= _trackingOptions.ImpossibleJumpSeconds && jumpMeters > _trackingOptions.ImpossibleJumpMeters)
            {
                throw new WalkLifecycleException("Location reading looked like a temporary GPS jump and was ignored.");
            }
        }

        var previousLocation = session.LastKnownLocation;
        var nextStop = session.NextStop;
        double? distanceToNext = nextStop is null ? null : RouteMath.DistanceMeters(command.Location, nextStop.Location);
        var routeDistance = RouteMath.DistanceFromRouteMeters(command.Location, session.Route.Coordinates);
        var noisePadding = Math.Max(command.AccuracyMeters ?? 0, 0);
        var routeProgress = Math.Max(session.ProgressPercentage, RouteMath.ProgressPercentage(command.Location, session.Route));
        var isOffRouteReading = routeDistance - noisePadding > _trackingOptions.OffRouteDistanceMeters;
        var offRouteCount = session.RecordOffRouteReading(isOffRouteReading);
        var isOffRoute = offRouteCount >= _trackingOptions.RequiredOffRouteReadings;
        var arrivalCandidate = false;
        var arrivalCandidateReadingCount = 0;
        WalkStop? confirmedArrival = null;
        string? arrivalCandidateStopId = null;

        if (nextStop is not null && distanceToNext is not null)
        {
            var arrivalThreshold = nextStop.ArrivalRadiusMeters + _trackingOptions.ArrivalAccuracyPaddingMeters;
            var crossedArrivalThreshold = previousLocation is not null
                && RouteMath.DistanceMeters(previousLocation, command.Location) <= _trackingOptions.ImpossibleJumpMeters
                && RouteMath.DistanceToSegmentMeters(nextStop.Location, previousLocation, command.Location) <= arrivalThreshold;
            if ((distanceToNext <= arrivalThreshold || crossedArrivalThreshold)
                && (command.AccuracyMeters ?? 0) <= _trackingOptions.MaximumAccuracyMeters)
            {
                var candidateCount = session.RecordArrivalCandidate(nextStop.StopId, true);
                arrivalCandidateReadingCount = candidateCount;
                arrivalCandidate = true;
                arrivalCandidateStopId = nextStop.StopId;
                if (candidateCount >= _trackingOptions.RequiredArrivalReadings)
                {
                    confirmedArrival = session.ArriveAtStop(nextStop.StopId, now, command.Location);
                    session.ClearArrivalCandidate();
                    nextStop = session.NextStop;
                    distanceToNext = nextStop is null ? null : RouteMath.DistanceMeters(command.Location, nextStop.Location);
                    routeProgress = Math.Max(session.ProgressPercentage, routeProgress);
                }
            }
            else
            {
                session.RecordArrivalCandidate(nextStop.StopId, false);
            }
        }

        var remaining = RouteMath.EstimateMinutesRemaining(session.Route, routeProgress);
        session.RecordLocation(
            command.Location,
            command.RecordedAtUtc,
            distanceToNext,
            routeProgress,
            remaining,
            isOffRoute,
            routeDistance,
            arrivalCandidate ? arrivalCandidateStopId : null);

        await _repository.UpdateAsync(session, cancellationToken);
        if (confirmedArrival is not null && _routeStoryPlans is not null)
        {
            await _routeStoryPlans.PrefetchUpcomingAsync(session, "automatic-arrival", cancellationToken);
        }

        return new LocationUpdateResult(
            session.WalkSessionId,
            session.Status,
            true,
            session.NextStop,
            distanceToNext,
            session.TrackingState.RouteProgressPercentage,
            session.TrackingState.EstimatedMinutesRemaining,
            session.TrackingState.IsOffRoute,
            session.TrackingState.DistanceFromRouteMeters,
            arrivalCandidate,
            arrivalCandidateReadingCount,
            arrivalCandidateStopId,
            confirmedArrival,
            now);
    }

    public async Task<WalkSession> ArriveAtStopAsync(string walkSessionId, string stopId, GeoLocation? currentLocation, CancellationToken cancellationToken)
    {
        var session = await GetRequiredAsync(walkSessionId, cancellationToken);
        if (session.Stops.All(candidate => !candidate.StopId.Equals(stopId, StringComparison.Ordinal)))
        {
            throw new KeyNotFoundException($"Stop '{stopId}' was not found.");
        }

        var stop = session.NextStop ?? throw new WalkLifecycleException("There is no next stop to arrive at.");
        if (!stop.StopId.Equals(stopId, StringComparison.Ordinal))
        {
            throw new WalkLifecycleException("Only the next ordered stop can be manually arrived.");
        }

        if (currentLocation is null)
        {
            throw new WalkLifecycleException("Manual arrival requires the current location.");
        }

        var distanceMeters = RouteMath.DistanceMeters(currentLocation, stop.Location);
        var allowedDistanceMeters = stop.ArrivalRadiusMeters + _trackingOptions.ManualArrivalExtraDistanceMeters;
        if (distanceMeters > allowedDistanceMeters)
        {
            throw new WalkLifecycleException("Manual arrival is available only when you are reasonably close to the next stop.");
        }

        session.ArriveAtStop(stopId, _timeProvider.GetUtcNow(), currentLocation);
        await _repository.UpdateAsync(session, cancellationToken);
        if (_routeStoryPlans is not null)
        {
            await _routeStoryPlans.PrefetchUpcomingAsync(session, "manual-arrival", cancellationToken);
        }
        return session;
    }

    public async Task<WalkSession> CompleteAsync(string walkSessionId, CancellationToken cancellationToken)
    {
        var session = await GetRequiredAsync(walkSessionId, cancellationToken);
        session.Complete(_timeProvider.GetUtcNow());
        await _repository.UpdateAsync(session, cancellationToken);
        return session;
    }

    public async Task<WalkSession> CancelAsync(string walkSessionId, CancellationToken cancellationToken)
    {
        var session = await GetRequiredAsync(walkSessionId, cancellationToken);
        session.Cancel(_timeProvider.GetUtcNow());
        await _repository.UpdateAsync(session, cancellationToken);
        return session;
    }

    private async Task<WalkSession> GetRequiredAsync(string walkSessionId, CancellationToken cancellationToken)
    {
        return await _repository.GetByIdAsync(walkSessionId, cancellationToken)
            ?? throw new KeyNotFoundException($"Walk session '{walkSessionId}' was not found.");
    }

}
