using Rover.Application.Walks;
using Rover.Application.Journeys;
using Rover.Domain.Walks;

namespace Rover.Application.Adaptations;

public sealed class WalkAdaptationService : IWalkAdaptationService
{
    private static readonly TimeSpan ProposalLifetime = TimeSpan.FromMinutes(10);

    private readonly IWalkSessionRepository _sessions;
    private readonly IWalkAdaptationRepository _adaptations;
    private readonly INearbyDiscoveryProvider _discoveries;
    private readonly IWalkRouteProvider _routes;
    private readonly IStopLifecycleConsistencyService _lifecycleConsistency;
    private readonly TimeProvider _timeProvider;
    private readonly IRouteStoryPlanService? _routeStoryPlans;
    private readonly IJourneyNarrativeArcService? _narrativeArcs;

    public WalkAdaptationService(
        IWalkSessionRepository sessions,
        IWalkAdaptationRepository adaptations,
        INearbyDiscoveryProvider discoveries,
        IWalkRouteProvider routes,
        TimeProvider timeProvider,
        IStopLifecycleConsistencyService? lifecycleConsistency = null,
        IRouteStoryPlanService? routeStoryPlans = null,
        IJourneyNarrativeArcService? narrativeArcs = null)
    {
        _sessions = sessions;
        _adaptations = adaptations;
        _discoveries = discoveries;
        _routes = routes;
        _lifecycleConsistency = lifecycleConsistency ?? new StopLifecycleConsistencyService();
        _timeProvider = timeProvider;
        _routeStoryPlans = routeStoryPlans;
        _narrativeArcs = narrativeArcs;
    }

    public async Task<WalkAdaptationProposal> EvaluateAsync(string walkSessionId, WalkAdaptationCommand command, CancellationToken cancellationToken)
    {
        var session = await GetMutableSession(walkSessionId, cancellationToken);
        EnsureActive(session);
        EnsureCurrentRevision(session, command.RouteRevision);

        var type = ResolveType(session, command);
        var currentLocation = command.CurrentLocation ?? session.LastKnownLocation ?? session.StartingLocation;
        var remaining = session.Stops.Where(stop => !stop.Visited).ToList();
        var proposed = remaining.ToList();
        var title = "Continue current walk";
        var explanation = "No route change is needed right now.";
        var affected = new List<string>();
        var addedMinutes = 0;
        var addedDistance = 0;
        WalkRoute? proposedRoute = null;

        switch (type)
        {
            case WalkAdaptationType.SkipStop:
                if (session.NextStop is not null)
                {
                    affected.Add(session.NextStop.StopId);
                    proposed.RemoveAll(stop => stop.StopId.Equals(session.NextStop.StopId, StringComparison.OrdinalIgnoreCase));
                    title = $"Skip {session.NextStop.Name}";
                    explanation = $"Rover can skip {session.NextStop.Name} and continue with the remaining ordered stops.";
                    addedMinutes = -session.NextStop.EstimatedVisitMinutes;
                    addedDistance = -session.NextStop.DistanceFromPreviousStopMeters;
                }
                break;

            case WalkAdaptationType.ShortenWalk:
                var removable = proposed
                    .OrderBy(stop => MatchesInterest(session, stop) ? 1 : 0)
                    .ThenByDescending(stop => stop.EstimatedVisitMinutes + stop.DistanceFromPreviousStopMeters / 80)
                    .Take(Math.Max(1, proposed.Count / 3))
                    .ToArray();
                affected.AddRange(removable.Select(stop => stop.StopId));
                proposed.RemoveAll(stop => removable.Any(remove => remove.StopId.Equals(stop.StopId, StringComparison.OrdinalIgnoreCase)));
                title = "Shorten the walk";
                explanation = "Rover can trim lower-priority remaining stops while preserving completed stops and high-interest stops where practical.";
                addedMinutes = -removable.Sum(stop => stop.EstimatedVisitMinutes);
                addedDistance = -removable.Sum(stop => stop.DistanceFromPreviousStopMeters);
                break;

            case WalkAdaptationType.ExtendWalk:
            case WalkAdaptationType.AddDiscovery:
                var discovery = await SelectDiscovery(session, currentLocation, command, cancellationToken);
                if (discovery is null && type == WalkAdaptationType.AddDiscovery)
                {
                    var requested = command.Interest ?? command.ProposedDiscoveryId ?? "nearby discovery";
                    title = $"No live {requested} option is available";
                    explanation = $"Rover could not add a live {requested} stop from the current location. The current walk is unchanged.";
                    break;
                }

                if (discovery is not null)
                {
                    var stop = discovery.ToStop(session.Stops.Count + 1);
                    var optimized = await InsertAtMostEfficientPositionAsync(
                        currentLocation,
                        command.AvailableMinutes ?? session.AvailableMinutes,
                        session,
                        proposed,
                        stop,
                        cancellationToken);
                    proposed = optimized.Stops;
                    proposedRoute = optimized.Route;
                    affected.Add(stop.StopId);
                    title = type == WalkAdaptationType.ExtendWalk ? $"Extend with {stop.Name}" : $"Add {stop.Name}";
                    explanation = discovery.SponsoredDisclosure is null
                        ? discovery.WhyRecommended
                        : $"{discovery.WhyRecommended} Sponsored: this recommendation is paid placement and will never be added without confirmation.";
                    addedMinutes = Math.Max(1, proposedRoute.DurationMinutes - session.Route.DurationMinutes);
                    addedDistance = Math.Max(0, proposedRoute.DistanceMeters - session.Route.DistanceMeters);
                }
                break;

            case WalkAdaptationType.RejoinRoute:
                title = "Rejoin the route";
                explanation = "Rover can route from your current location back to the next sensible unvisited stop without sending you backward unnecessarily.";
                addedMinutes = 4;
                addedDistance = 180;
                break;

            case WalkAdaptationType.ReturnToStart:
                proposed = new List<WalkStop>
                {
                    new WalkStop(
                        "return-to-starting-area",
                        session.Stops.Count + 1,
                        "Return to Starting Area",
                        session.StartingLocation,
                        "Return safely to where this walk began.",
                        "Rover will guide you back toward the starting area and end the walk there.",
                        "Return",
                        ContentType.History,
                        ContentSource.RoverEditorial,
                        2,
                        (int)Math.Round(Walks.RouteMath.DistanceMeters(currentLocation, session.StartingLocation)),
                        WalkGeofenceDefaults.StandardArrivalRadiusMeters)
                };
                affected.Add("return-to-starting-area");
                title = "Return to the starting area";
                explanation = "Rover can replace remaining stops with a direct return to the start.";
                addedMinutes = 2;
                addedDistance = proposed[0].DistanceFromPreviousStopMeters;
                break;
        }

        if (proposed.Count == 0)
        {
            proposed.AddRange(remaining.Take(1));
        }

        var previousRemainingIds = remaining.Select(stop => stop.StopId).ToArray();
        var proposedIds = proposed.Select(stop => stop.StopId).ToArray();
        var addedStops = proposedIds.Except(previousRemainingIds, StringComparer.OrdinalIgnoreCase).ToArray();
        var removedStops = previousRemainingIds.Except(proposedIds, StringComparer.OrdinalIgnoreCase).ToArray();
        var reorderedStops = proposedIds;

        var route = proposedRoute ?? await _routes.CreateRouteAsync(
            RouteCommand(currentLocation, command.AvailableMinutes ?? session.AvailableMinutes, session),
            proposed,
            cancellationToken);

        var now = _timeProvider.GetUtcNow();
        var proposal = new WalkAdaptationProposal(
            Guid.NewGuid().ToString("n"),
            session.WalkSessionId,
            type,
            title,
            explanation,
            addedMinutes,
            addedDistance,
            Math.Max(0, session.Route.DurationMinutes + addedMinutes),
            affected,
            addedStops,
            removedStops,
            reorderedStops,
            route,
            proposed,
            session.RouteRevision,
            now,
            now.Add(ProposalLifetime));

        await _adaptations.AddAsync(proposal, cancellationToken);
        return proposal;
    }

    public Task<WalkAdaptationProposal?> GetAsync(string walkSessionId, string adaptationId, CancellationToken cancellationToken)
    {
        return _adaptations.GetAsync(walkSessionId, adaptationId, cancellationToken);
    }

    public async Task<WalkSession> AcceptAsync(string walkSessionId, string adaptationId, int routeRevision, CancellationToken cancellationToken)
    {
        var session = await GetMutableSession(walkSessionId, cancellationToken);
        var proposal = await _adaptations.GetAsync(walkSessionId, adaptationId, cancellationToken)
            ?? throw new KeyNotFoundException($"Adaptation '{adaptationId}' was not found.");

        if (proposal.Status == WalkAdaptationStatus.Applied)
        {
            return session;
        }

        EnsureActive(session);
        EnsureCurrentRevision(session, routeRevision);

        try
        {
            proposal.Accept(_timeProvider.GetUtcNow());
            var appliedAtUtc = _timeProvider.GetUtcNow();
            session.ApplyAdaptation(proposal, appliedAtUtc);
            _lifecycleConsistency.RepairRecoverable(session, appliedAtUtc);
            proposal.Applied();
            await _sessions.UpdateAsync(session, cancellationToken);
            await _adaptations.UpdateAsync(proposal, cancellationToken);
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
        catch
        {
            if (proposal.Status == WalkAdaptationStatus.Accepted)
            {
                proposal.Fail();
                await _adaptations.UpdateAsync(proposal, cancellationToken);
            }

            throw;
        }
    }

    public async Task<WalkAdaptationProposal> RejectAsync(string walkSessionId, string adaptationId, CancellationToken cancellationToken)
    {
        var proposal = await _adaptations.GetAsync(walkSessionId, adaptationId, cancellationToken)
            ?? throw new KeyNotFoundException($"Adaptation '{adaptationId}' was not found.");

        proposal.Reject();
        await _adaptations.UpdateAsync(proposal, cancellationToken);
        return proposal;
    }

    private async Task<WalkSession> GetMutableSession(string walkSessionId, CancellationToken cancellationToken)
    {
        return await _sessions.GetByIdAsync(walkSessionId, cancellationToken)
            ?? throw new KeyNotFoundException($"Walk session '{walkSessionId}' was not found.");
    }

    private static void EnsureActive(WalkSession session)
    {
        if (session.Status is WalkSessionStatus.Completed or WalkSessionStatus.Cancelled)
        {
            throw new WalkLifecycleException("Completed and Cancelled walks cannot be adapted.");
        }
    }

    private static void EnsureCurrentRevision(WalkSession session, int routeRevision)
    {
        if (routeRevision != session.RouteRevision)
        {
            throw new WalkLifecycleException("Route revision is stale. Refresh the walk before adapting it.");
        }
    }

    private static WalkAdaptationType ResolveType(WalkSession session, WalkAdaptationCommand command)
    {
        if (command.RequestedType is not null)
        {
            return command.RequestedType.Value;
        }

        var text = command.UserRequest?.ToLowerInvariant() ?? string.Empty;
        if (text.Contains("skip")) return WalkAdaptationType.SkipStop;
        if (text.Contains("short") || text.Contains("only have")) return WalkAdaptationType.ShortenWalk;
        if (text.Contains("longer") || text.Contains("extend")) return WalkAdaptationType.ExtendWalk;
        if (text.Contains("back") || text.Contains("return")) return WalkAdaptationType.ReturnToStart;
        if (text.Contains("rejoin") || session.TrackingState.IsOffRoute) return WalkAdaptationType.RejoinRoute;
        if (text.Contains("coffee") || text.Contains("nearby") || text.Contains("find")) return WalkAdaptationType.AddDiscovery;
        return WalkAdaptationType.ContinueUnchanged;
    }

    private async Task<NearbyDiscovery?> SelectDiscovery(WalkSession session, GeoLocation currentLocation, WalkAdaptationCommand command, CancellationToken cancellationToken)
    {
        var discoveries = await _discoveries.FindAsync(session, currentLocation, command.Interest, command.DismissedDiscoveryIds, cancellationToken);
        if (!string.IsNullOrWhiteSpace(command.ProposedDiscoveryId))
        {
            return discoveries.FirstOrDefault(discovery => discovery.DiscoveryId.Equals(command.ProposedDiscoveryId, StringComparison.OrdinalIgnoreCase))
                ?? discoveries.FirstOrDefault();
        }

        return discoveries.FirstOrDefault();
    }

    private async Task<(List<WalkStop> Stops, WalkRoute Route)> InsertAtMostEfficientPositionAsync(
        GeoLocation currentLocation,
        int availableMinutes,
        WalkSession session,
        IReadOnlyList<WalkStop> remainingStops,
        WalkStop addedStop,
        CancellationToken cancellationToken)
    {
        List<WalkStop>? bestStops = null;
        WalkRoute? bestRoute = null;
        double? bestScore = null;
        var command = RouteCommand(currentLocation, availableMinutes, session);

        for (var index = 0; index <= remainingStops.Count; index++)
        {
            var candidateStops = remainingStops.ToList();
            candidateStops.Insert(index, addedStop);
            var candidateRoute = await _routes.CreateRouteAsync(command, candidateStops, cancellationToken);
            var candidateScore = ScoreCandidateRoute(currentLocation, availableMinutes, candidateStops, candidateRoute);
            if (bestRoute is null
                || bestScore is null
                || candidateScore < bestScore
                || (Math.Abs(candidateScore - bestScore.Value) < 0.01
                    && candidateRoute.DistanceMeters < bestRoute.DistanceMeters))
            {
                bestStops = candidateStops;
                bestRoute = candidateRoute;
                bestScore = candidateScore;
            }
        }

        return (bestStops ?? remainingStops.Append(addedStop).ToList(), bestRoute!);
    }

    private static double ScoreCandidateRoute(
        GeoLocation currentLocation,
        int availableMinutes,
        IReadOnlyList<WalkStop> candidateStops,
        WalkRoute candidateRoute)
    {
        var stopMinutes = candidateStops.Sum(stop => Math.Max(0, stop.EstimatedVisitMinutes));
        var experienceMinutes = Math.Max(0, candidateRoute.DurationMinutes) + stopMinutes;
        var targetMinutes = Math.Max(15, availableMinutes);
        var utilizationGap = Math.Abs(targetMinutes - experienceMinutes);
        var backtrackingMeters = EstimateBacktrackingMeters(currentLocation, candidateStops);
        var terminalDistanceMeters = candidateStops.Count == 0
            ? 0
            : Walks.RouteMath.DistanceMeters(candidateStops[^1].Location, currentLocation);

        return candidateRoute.DurationMinutes * 60
            + candidateRoute.DistanceMeters * 0.15
            + utilizationGap * 90
            + backtrackingMeters * 0.45
            + terminalDistanceMeters * 0.08;
    }

    private static double EstimateBacktrackingMeters(GeoLocation currentLocation, IReadOnlyList<WalkStop> stops)
    {
        if (stops.Count < 2)
        {
            return 0;
        }

        var points = new[] { currentLocation }.Concat(stops.Select(stop => stop.Location)).ToArray();
        var excessMeters = 0d;
        for (var index = 1; index < points.Length - 1; index++)
        {
            var direct = Walks.RouteMath.DistanceMeters(points[index - 1], points[index + 1]);
            if (direct <= 0)
            {
                continue;
            }

            var viaCurrent = Walks.RouteMath.DistanceMeters(points[index - 1], points[index])
                + Walks.RouteMath.DistanceMeters(points[index], points[index + 1]);
            if (viaCurrent / direct >= 1.75)
            {
                excessMeters += viaCurrent - direct;
            }
        }

        return excessMeters;
    }

    private static CreateWalkCommand RouteCommand(GeoLocation currentLocation, int availableMinutes, WalkSession session)
    {
        return new CreateWalkCommand(
            currentLocation,
            Math.Max(15, availableMinutes),
            session.Interests,
            session.WalkingPace,
            session.AccessibilityPreferences);
    }

    private static bool MatchesInterest(WalkSession session, WalkStop stop)
    {
        return session.Interests.Any(interest =>
            stop.Category.Contains(interest, StringComparison.OrdinalIgnoreCase)
            || stop.Name.Contains(interest, StringComparison.OrdinalIgnoreCase)
            || stop.ShortDescription.Contains(interest, StringComparison.OrdinalIgnoreCase));
    }
}
