namespace Rover.Domain.Walks;

public sealed class WalkSession
{
    private readonly List<WalkStop> _stops;
    private readonly List<WalkRouteRevision> _routeRevisions = new();

    public WalkSession(
        string walkSessionId,
        GeoLocation startingLocation,
        DateTimeOffset createdAtUtc,
        int availableMinutes,
        int estimatedDurationMinutes,
        int estimatedDistanceMeters,
        string routeSummary,
        IReadOnlyCollection<string> interests,
        WalkingPace walkingPace,
        IReadOnlyCollection<AccessibilityPreference> accessibilityPreferences,
        IEnumerable<WalkStop> stops,
        WalkRoute? route = null)
    {
        WalkSessionId = walkSessionId;
        StartingLocation = startingLocation;
        CreatedAtUtc = createdAtUtc;
        AvailableMinutes = availableMinutes;
        EstimatedDurationMinutes = estimatedDurationMinutes;
        EstimatedDistanceMeters = estimatedDistanceMeters;
        RouteSummary = routeSummary;
        Interests = interests.ToArray();
        WalkingPace = walkingPace;
        AccessibilityPreferences = accessibilityPreferences.ToArray();
        _stops = stops.OrderBy(stop => stop.SequenceNumber).ToList();
        Route = route ?? CreateStopRoute(walkSessionId, createdAtUtc, _stops);
        OriginalRoute = Route;
        RouteRevision = 1;
        _routeRevisions.Add(new WalkRouteRevision(RouteRevision, "Original route", createdAtUtc, Array.Empty<string>(), Array.Empty<string>(), _stops.Select(stop => stop.StopId).ToArray()));
        TrackingState = new WalkTrackingState(null, ProgressPercentage, TimeRemainingMinutes, false, 0, null, null);
        Status = WalkSessionStatus.Created;
        MarkReady();
    }

    public string WalkSessionId { get; }
    public WalkSessionStatus Status { get; private set; }
    public GeoLocation StartingLocation { get; }
    public GeoLocation? LastKnownLocation { get; private set; }
    public DateTimeOffset CreatedAtUtc { get; }
    public DateTimeOffset? StartedAtUtc { get; private set; }
    public DateTimeOffset? CompletedAtUtc { get; private set; }
    public DateTimeOffset? CancelledAtUtc { get; private set; }
    public int AvailableMinutes { get; private set; }
    public int EstimatedDurationMinutes { get; private set; }
    public int EstimatedDistanceMeters { get; private set; }
    public string RouteSummary { get; }
    public IReadOnlyCollection<string> Interests { get; }
    public WalkingPace WalkingPace { get; }
    public IReadOnlyCollection<AccessibilityPreference> AccessibilityPreferences { get; }
    public IReadOnlyList<WalkStop> Stops => _stops;
    public WalkRoute Route { get; private set; }
    public WalkRoute OriginalRoute { get; }
    public int RouteRevision { get; private set; }
    public IReadOnlyList<WalkRouteRevision> RouteRevisions => _routeRevisions;
    public WalkTrackingState TrackingState { get; private set; }
    public string? RecentNarrationStopId { get; private set; }
    public string? ArrivalCandidateStopId { get; private set; }
    public int ArrivalCandidateReadingCount { get; private set; }
    public int OffRouteReadingCount { get; private set; }

    public int VisitedStopCount => _stops.Count(stop => stop.Visited);
    public int TimeRemainingMinutes => Math.Max(0, AvailableMinutes - _stops.Where(stop => stop.Visited).Sum(stop => stop.EstimatedVisitMinutes));
    public double ProgressPercentage => _stops.Count == 0 ? 0 : Math.Round((double)VisitedStopCount / _stops.Count * 100, 2);

    public WalkStop? NextStop => _stops.FirstOrDefault(stop => !stop.Visited);

    public void SetRoute(WalkRoute route)
    {
        Route = route;
    }

    public void ApplyAdaptation(WalkAdaptationProposal proposal, DateTimeOffset appliedAtUtc)
    {
        if (Status is WalkSessionStatus.Completed or WalkSessionStatus.Cancelled)
        {
            throw new WalkLifecycleException("Completed and Cancelled walks cannot be changed.");
        }

        if (proposal.RouteRevision != RouteRevision)
        {
            throw new WalkLifecycleException("The adaptation was created for an older route revision.");
        }

        var previousStopIds = _stops.Select(stop => stop.StopId).ToArray();
        var visitedStops = _stops.Where(stop => stop.Visited).ToArray();
        var visitedStopIds = visitedStops.Select(stop => stop.StopId).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var remainingStops = proposal.ProposedStops
            .Where(stop => !visitedStopIds.Contains(stop.StopId))
            .ToArray();

        _stops.Clear();
        _stops.AddRange(RenumberStops(visitedStops.Concat(remainingStops)));
        Route = proposal.ProposedRoute;
        RouteRevision++;
        EstimatedDistanceMeters = Route.DistanceMeters;
        EstimatedDurationMinutes = Math.Min(AvailableMinutes, proposal.EstimatedNewTotalMinutes);
        ClearArrivalCandidate();
        TrackingState = TrackingState with
        {
            DistanceToNextStopMeters = NextStop is null || LastKnownLocation is null
                ? null
                : DistanceMeters(LastKnownLocation, NextStop.Location),
            EstimatedMinutesRemaining = Math.Max(0, proposal.EstimatedNewTotalMinutes - visitedStops.Sum(stop => stop.EstimatedVisitMinutes)),
            IsOffRoute = proposal.Type != WalkAdaptationType.RejoinRoute && TrackingState.IsOffRoute,
            RouteProgressPercentage = proposal.Type == WalkAdaptationType.RejoinRoute
                ? 0
                : TrackingState.RouteProgressPercentage,
            DistanceFromRouteMeters = proposal.Type == WalkAdaptationType.RejoinRoute
                ? 0
                : TrackingState.DistanceFromRouteMeters,
            ArrivalCandidateStopId = null,
            LastLocationRecordedAtUtc = appliedAtUtc
        };

        var newStopIds = _stops.Select(stop => stop.StopId).ToArray();
        var added = newStopIds.Except(previousStopIds, StringComparer.OrdinalIgnoreCase).ToArray();
        var removed = previousStopIds.Except(newStopIds, StringComparer.OrdinalIgnoreCase).ToArray();
        _routeRevisions.Add(new WalkRouteRevision(
            RouteRevision,
            proposal.Title,
            appliedAtUtc,
            added,
            removed,
            newStopIds));
    }

    public IReadOnlyList<string> RepairRecoverableLifecycle(DateTimeOffset repairedAtUtc)
    {
        var repairs = new List<string>();

        if (_stops.Where((stop, index) => stop.SequenceNumber != index + 1).Any())
        {
            var renumbered = RenumberStops(_stops);
            _stops.Clear();
            _stops.AddRange(renumbered);
            repairs.Add("Stop sequence numbers were normalized.");
        }

        var nextStop = NextStop;
        if (ArrivalCandidateStopId is not null &&
            (nextStop is null || !ArrivalCandidateStopId.Equals(nextStop.StopId, StringComparison.OrdinalIgnoreCase)))
        {
            ClearArrivalCandidate();
            repairs.Add("Stale arrival-candidate state was cleared.");
        }

        if (TrackingState.ArrivalCandidateStopId is not null &&
            (nextStop is null || !TrackingState.ArrivalCandidateStopId.Equals(nextStop.StopId, StringComparison.OrdinalIgnoreCase)))
        {
            TrackingState = TrackingState with
            {
                ArrivalCandidateStopId = null,
                LastLocationRecordedAtUtc = repairedAtUtc
            };
            repairs.Add("Stale tracking arrival-candidate state was cleared.");
        }

        if (Route.Coordinates.Count < 2 && _stops.Count > 0)
        {
            Route = CreateStopRoute(WalkSessionId, repairedAtUtc, _stops);
            RouteRevision++;
            _routeRevisions.Add(new WalkRouteRevision(
                RouteRevision,
                "Recovered route geometry",
                repairedAtUtc,
                Array.Empty<string>(),
                Array.Empty<string>(),
                _stops.Select(stop => stop.StopId).ToArray()));
            repairs.Add("Route geometry was rebuilt from the ordered stops.");
        }

        return repairs;
    }

    public void Start(DateTimeOffset startedAtUtc)
    {
        if (Status != WalkSessionStatus.Ready)
        {
            throw new WalkLifecycleException("Only a Ready walk can be started.");
        }

        Status = WalkSessionStatus.InProgress;
        StartedAtUtc = startedAtUtc;
        LastKnownLocation = StartingLocation;
    }

    public WalkStop ArriveAtStop(string stopId, DateTimeOffset arrivedAtUtc, GeoLocation? currentLocation = null)
    {
        if (Status != WalkSessionStatus.InProgress)
        {
            throw new WalkLifecycleException("Stop arrival is allowed only while a walk is InProgress.");
        }

        var stop = _stops.FirstOrDefault(candidate => candidate.StopId.Equals(stopId, StringComparison.OrdinalIgnoreCase));
        if (stop is null)
        {
            throw new KeyNotFoundException($"Stop '{stopId}' was not found.");
        }

        var nextStop = NextStop;
        if (nextStop is null)
        {
            throw new WalkLifecycleException("All stops have already been visited.");
        }

        if (!nextStop.StopId.Equals(stop.StopId, StringComparison.OrdinalIgnoreCase))
        {
            throw new WalkLifecycleException("Stops must be arrived at in sequence.");
        }

        stop.MarkArrived(arrivedAtUtc);
        LastKnownLocation = currentLocation ?? stop.Location;
        RecentNarrationStopId = stop.StopId;

        return stop;
    }

    public void RecordLocation(
        GeoLocation location,
        DateTimeOffset recordedAtUtc,
        double? distanceToNextStopMeters,
        double routeProgressPercentage,
        int estimatedMinutesRemaining,
        bool isOffRoute,
        double distanceFromRouteMeters,
        string? arrivalCandidateStopId)
    {
        LastKnownLocation = location;
        TrackingState = new WalkTrackingState(
            distanceToNextStopMeters,
            Math.Clamp(Math.Max(ProgressPercentage, routeProgressPercentage), 0, 100),
            Math.Max(0, estimatedMinutesRemaining),
            isOffRoute,
            Math.Max(0, distanceFromRouteMeters),
            arrivalCandidateStopId,
            recordedAtUtc);
    }

    public int RecordArrivalCandidate(string stopId, bool qualifies)
    {
        if (!qualifies)
        {
            ArrivalCandidateStopId = null;
            ArrivalCandidateReadingCount = 0;
            return 0;
        }

        if (!string.Equals(ArrivalCandidateStopId, stopId, StringComparison.OrdinalIgnoreCase))
        {
            ArrivalCandidateStopId = stopId;
            ArrivalCandidateReadingCount = 0;
        }

        ArrivalCandidateReadingCount++;
        return ArrivalCandidateReadingCount;
    }

    public int RecordOffRouteReading(bool qualifies)
    {
        OffRouteReadingCount = qualifies ? OffRouteReadingCount + 1 : 0;
        return OffRouteReadingCount;
    }

    public void ClearArrivalCandidate()
    {
        ArrivalCandidateStopId = null;
        ArrivalCandidateReadingCount = 0;
    }

    public void Complete(DateTimeOffset completedAtUtc)
    {
        if (Status != WalkSessionStatus.InProgress)
        {
            throw new WalkLifecycleException("Only an InProgress walk can be completed.");
        }

        if (NextStop is not null)
        {
            throw new WalkLifecycleException("All stops must be visited before completing the walk.");
        }

        Status = WalkSessionStatus.Completed;
        CompletedAtUtc = completedAtUtc;
    }

    public void Cancel(DateTimeOffset cancelledAtUtc)
    {
        if (Status is WalkSessionStatus.Completed or WalkSessionStatus.Cancelled)
        {
            throw new WalkLifecycleException("Completed and Cancelled walks cannot be changed.");
        }

        Status = WalkSessionStatus.Cancelled;
        CancelledAtUtc = cancelledAtUtc;
    }

    private void MarkReady()
    {
        if (_stops.Count == 0)
        {
            throw new WalkLifecycleException("A walk requires at least one stop.");
        }

        Status = WalkSessionStatus.Ready;
    }

    private static WalkRoute CreateStopRoute(string walkSessionId, DateTimeOffset generatedAtUtc, IReadOnlyList<WalkStop> stops)
    {
        var coordinates = stops.Select(stop => stop.Location).ToArray();
        var bounds = new RouteBounds(
            new GeoLocation(coordinates.Min(point => point.Latitude), coordinates.Min(point => point.Longitude)),
            new GeoLocation(coordinates.Max(point => point.Latitude), coordinates.Max(point => point.Longitude)));

        return new WalkRoute(
            $"mock-{walkSessionId}",
            "Mock",
            "union-square-v1",
            generatedAtUtc,
            coordinates,
            bounds,
            stops.Sum(stop => stop.DistanceFromPreviousStopMeters),
            stops.Sum(stop => stop.EstimatedVisitMinutes),
            stops.Select((stop, index) => new WalkRouteManeuver(
                index + 1,
                $"Walk to stop {index + 1}: {stop.Name}.",
                index == 0 ? 0 : stop.DistanceFromPreviousStopMeters,
                Math.Max(1, stop.DistanceFromPreviousStopMeters / 80))).ToArray());
    }

    private static IReadOnlyList<WalkStop> RenumberStops(IEnumerable<WalkStop> stops)
    {
        return stops
            .Select((stop, index) =>
            {
                var copy = new WalkStop(
                    stop.StopId,
                    index + 1,
                    stop.Name,
                    stop.Location,
                    stop.ShortDescription,
                    stop.Narration,
                    stop.Category,
                    stop.ContentType,
                    stop.ContentSource,
                    stop.EstimatedVisitMinutes,
                    index == 0 ? 0 : stop.DistanceFromPreviousStopMeters,
                    stop.ArrivalRadiusMeters,
                    stop.SponsoredDisclosure,
                    stop.Address,
                    stop.WebsiteUrl,
                    stop.PhoneNumber,
                    stop.MenuUrl);

                if (stop.ArrivedAtUtc is not null)
                {
                    copy.MarkArrived(stop.ArrivedAtUtc.Value);
                }

                return copy;
            })
            .ToArray();
    }

    private static double DistanceMeters(GeoLocation a, GeoLocation b)
    {
        const double radiusMeters = 6371000;
        var dLat = DegreesToRadians(b.Latitude - a.Latitude);
        var dLng = DegreesToRadians(b.Longitude - a.Longitude);
        var lat1 = DegreesToRadians(a.Latitude);
        var lat2 = DegreesToRadians(b.Latitude);
        var h = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
            + Math.Cos(lat1) * Math.Cos(lat2) * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return 2 * radiusMeters * Math.Asin(Math.Min(1, Math.Sqrt(h)));
    }

    private static double DegreesToRadians(double degrees) => degrees * Math.PI / 180;
}
