using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Walks;

public sealed class MockWalkPlanner : IWalkPlanner
{
    private readonly IWalkRouteProvider _routeProvider;
    private readonly ILocalDiscoveryProvider _localDiscoveryProvider;
    private readonly IStoryLedStopSelector? _storySelector;
    private readonly WalkPlaceSearchService? _placeSearch;

    public MockWalkPlanner()
        : this(new MockWalkRouteProvider(), new NoOpLocalDiscoveryProvider())
    {
    }

    public MockWalkPlanner(IWalkRouteProvider routeProvider, ILocalDiscoveryProvider? localDiscoveryProvider = null,
        IStoryLedStopSelector? storySelector = null, WalkPlaceSearchService? placeSearch = null)
    {
        _routeProvider = routeProvider;
        _localDiscoveryProvider = localDiscoveryProvider ?? new NoOpLocalDiscoveryProvider();
        _storySelector = storySelector;
        _placeSearch = placeSearch;
    }

    public async Task<WalkSession> PlanWalkAsync(CreateWalkCommand command, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (command.SelectedPlace is not null)
            return await PlanSelectedPlaceAsync(command, cancellationToken);

        var storyPlanning = _storySelector?.Enabled == true;
        var isUnionSquareStart = !storyPlanning && !_localDiscoveryProvider.RequiresRealPlaces
            && RouteMath.DistanceMeters(command.StartingLocation, new GeoLocation(37.7880, -122.4075)) < 5_000;
        var desiredStops = DesiredStopCount(command.AvailableMinutes);
        var discovery = isUnionSquareStart
            ? new LocalDiscoveryResult(Array.Empty<WalkStop>(), null)
            : await _localDiscoveryProvider.DiscoverForPlanningAsync(command, cancellationToken, 30);
        IReadOnlyList<WalkStop> discoveredStops = discovery.Stops.Where(stop => WalkInterestPolicy.Allows(stop, command.Interests)).ToArray();
        if (_localDiscoveryProvider.RequiresRealPlaces && discoveredStops.Count < 2)
            throw new InvalidOperationException("A real-place walk could not be created: fewer than two usable places were found. "
                + discovery.Diagnostic + " No fallback waypoints were created.");
        if (_localDiscoveryProvider.RequiresRealPlaces && discoveredStops.Count >= 2 &&
            discoveredStops.All(stop => RouteMath.DistanceMeters(command.StartingLocation, stop.Location) < command.AvailableMinutes * 10))
        {
            var expanded = discoveredStops.ToList();
            foreach (var center in ExploreEitherSide(command.StartingLocation, command.StartingLocation,
                discoveredStops[^1].Location, Math.Clamp(command.AvailableMinutes * 14, 300, 1400)))
            {
                var more = await _localDiscoveryProvider.DiscoverForPlanningAsync(command with { StartingLocation = center }, cancellationToken, 15);
                expanded.AddRange(more.Stops.Where(stop => WalkInterestPolicy.Allows(stop, command.Interests)));
            }
            discoveredStops = expanded.DistinctBy(stop => stop.StopId).ToArray();
        }
        var selection = storyPlanning
            ? await _storySelector!.SelectAsync(command, discoveredStops, desiredStops, cancellationToken)
            : null;
        var stops = isUnionSquareStart
            ? Resequence(command.StartingLocation, CreateUnionSquareStops().Where(stop => WalkInterestPolicy.Allows(stop, command.Interests)).ToArray())
            : selection?.Stops.Count >= 2
            ? CreateEfficientStopPlan(command, WalkInterestPolicy.TakeBalanced(
                selection.Stops.Concat(discoveredStops).DistinctBy(stop => stop.StopId), selection.Stops.Count,
                command.Interests, WalkInterestPolicy.Group), selection.Stops.Count)
            : discoveredStops.Count >= 2
            ? CreateEfficientStopPlan(command, discoveredStops, desiredStops, balanceInterests: true)
            : CreateLocalWaypointStops(command.StartingLocation);
        var route = await _routeProvider.CreateRouteAsync(command, stops, cancellationToken);
        // Walking and visits share one budget. Each reroute removes at least one
        // optional stop, so this loop is bounded by the original stop count.
        while (stops.Count > 2 && route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes) > command.AvailableMinutes)
        {
            var total = route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes);
            var count = Math.Clamp((int)Math.Floor(stops.Count * command.AvailableMinutes / (double)total), 2, stops.Count - 1);
            var retainedIds = stops.Select(stop => stop.StopId).ToHashSet();
            var rankedStops = (selection?.Stops ?? []).Where(stop => retainedIds.Contains(stop.StopId))
                .Concat(stops).DistinctBy(stop => stop.StopId);
            var retained = WalkInterestPolicy.TakeBalanced(rankedStops, count, command.Interests, WalkInterestPolicy.Group);
            stops = CreateEfficientStopPlan(command, retained, retained.Length);
            route = await _routeProvider.CreateRouteAsync(command, stops, cancellationToken);
        }
        if (discoveredStops.Count >= 2)
            (stops, route) = await FillAvailableTimeAsync(command, stops, route, discoveredStops, cancellationToken, balanceInterests: true);
        var estimatedDurationMinutes = route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes);
        var estimatedDistanceMeters = route.DistanceMeters;
        var summary = isUnionSquareStart
            ? "A compact Union Square loop with architecture, public art, shopping history, and one clearly disclosed sponsored stop."
            : discoveredStops.Count >= 2
            ? "A live local walk using nearby places and walking-route geometry."
            : "A short local walk generated around your selected starting area.";
        if (selection is not null)
        {
            summary += selection.Stops.Count >= 2
                ? $" Story-led planning: {selection.Status}; {stops.Count} stops retained."
                : $" Story-led planning fallback: {selection.Status}.";
        }
        if (estimatedDurationMinutes > command.AvailableMinutes)
            summary += " This route exceeds your requested time; review the estimate before starting.";

        summary += TimingSummary(command, route, stops);
        var session = new WalkSession(
            Guid.NewGuid().ToString("n"),
            command.StartingLocation,
            DateTimeOffset.UtcNow,
            command.AvailableMinutes,
            estimatedDurationMinutes,
            estimatedDistanceMeters,
            summary,
            command.Interests,
            command.WalkingPace,
            command.AccessibilityPreferences,
            stops,
            route) { ProfileId = command.ProfileId };

        return session;
    }

    private static int DesiredStopCount(int availableMinutes)
    {
        return Math.Clamp((int)Math.Round(availableMinutes / 8d), 3, 12);
    }

    private static IReadOnlyList<WalkStop> CreateEfficientStopPlan(
        CreateWalkCommand command,
        IReadOnlyList<WalkStop> candidates,
        int desiredStops, bool balanceInterests = false)
    {
        var uniqueCandidates = candidates
            .GroupBy(stop => string.IsNullOrWhiteSpace(stop.StopId) ? stop.Name : stop.StopId, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderBy(stop => RouteMath.DistanceMeters(command.StartingLocation, stop.Location)).First())
            .ToArray();
        var selected = SelectGeographicallyVariedStops(
            command.StartingLocation,
            uniqueCandidates,
            Math.Clamp(desiredStops, 2, 12));

        if (balanceInterests)
            selected = WalkInterestPolicy.TakeBalanced(selected.Concat(uniqueCandidates).DistinctBy(stop => stop.StopId),
                selected.Length, command.Interests, WalkInterestPolicy.Group);

        if (selected.Length <= 2)
        {
            return Resequence(command.StartingLocation, selected);
        }

        var ordered = new List<WalkStop> { selected.OrderBy(stop => RouteMath.DistanceMeters(command.StartingLocation, stop.Location)).First() };
        foreach (var stop in selected.Where(stop => !ReferenceEquals(stop, ordered[0])))
        {
            var bestIndex = 0;
            var bestDistance = double.MaxValue;
            for (var index = 1; index <= ordered.Count; index++)
            {
                var candidate = ordered.ToList();
                candidate.Insert(index, stop);
                var distance = PlannedDistance(command.StartingLocation, candidate);
                if (distance < bestDistance)
                {
                    bestDistance = distance;
                    bestIndex = index;
                }
            }

            ordered.Insert(bestIndex, stop);
        }

        return Resequence(command.StartingLocation, ordered);
    }

    private static WalkStop[] SelectGeographicallyVariedStops(
        GeoLocation start,
        IReadOnlyList<WalkStop> candidates,
        int desiredStops)
    {
        if (candidates.Count <= desiredStops)
        {
            return candidates.ToArray();
        }

        var selected = new List<WalkStop>
        {
            candidates.OrderBy(stop => RouteMath.DistanceMeters(start, stop.Location)).First()
        };
        var remaining = candidates.Where(stop => !ReferenceEquals(stop, selected[0])).ToList();
        while (selected.Count < desiredStops && remaining.Count > 0)
        {
            var next = remaining
                .OrderByDescending(stop => selected.Min(chosen => RouteMath.DistanceMeters(chosen.Location, stop.Location)))
                .ThenBy(stop => RouteMath.DistanceMeters(start, stop.Location))
                .First();
            selected.Add(next);
            remaining.Remove(next);
        }

        return selected.ToArray();
    }

    private static double PlannedDistance(GeoLocation start, IReadOnlyList<WalkStop> orderedStops)
    {
        var total = 0d;
        var previous = start;
        foreach (var stop in orderedStops)
        {
            total += RouteMath.DistanceMeters(previous, stop.Location);
            previous = stop.Location;
        }

        return total;
    }

    private static IReadOnlyList<WalkStop> Resequence(GeoLocation start, IReadOnlyList<WalkStop> stops)
    {
        var previous = start;
        var resequenced = new List<WalkStop>(stops.Count);
        for (var index = 0; index < stops.Count; index++)
        {
            var stop = stops[index];
            var distance = (int)Math.Round(RouteMath.DistanceMeters(previous, stop.Location));
            resequenced.Add(new WalkStop(
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
                distance,
                stop.ArrivalRadiusMeters,
                stop.SponsoredDisclosure,
                stop.Address,
                stop.WebsiteUrl,
                stop.PhoneNumber,
                stop.MenuUrl,
                stop.DiscoveryProviderName,
                stop.ProviderPlaceId,
                stop.SourceUrl,
                stop.RequiredAttribution) { IsDestination = stop.IsDestination });
            previous = stop.Location;
        }

        return resequenced;
    }

    private async Task<WalkSession> PlanSelectedPlaceAsync(CreateWalkCommand command, CancellationToken ct)
    {
        var requested = await (_placeSearch ?? throw new InvalidOperationException("Place search is unavailable."))
            .ResolveAsync(command.SelectedPlace!, command.StartingLocation, ct);
        return await PlanToPlaceAsync(command, requested, ct);
    }

    public async Task<WalkSession> PlanToPlaceAsync(CreateWalkCommand command, WalkStop requested, CancellationToken ct)
    {
        var direct = await _routeProvider.CreateRouteAsync(command, new[] { requested }, ct);
        EnsureSelectedPlaceRoute(direct);
        var candidates = new List<WalkStop>();
        // Bounded corridor discovery uses the same interests and accessibility
        // preferences as normal planning, along the actual walking geometry.
        if (direct.DurationMinutes + requested.EstimatedVisitMinutes < command.AvailableMinutes)
        {
            var geometry = direct.Coordinates;
            var spareMinutes = command.AvailableMinutes - direct.DurationMinutes - requested.EstimatedVisitMinutes;
            var detourRadius = Math.Clamp(spareMinutes * 20, 600, 1600);
            var centers = CorridorCenters(geometry, 450, 12).ToList();
            if (spareMinutes >= 20 && centers.Count <= 6)
                centers.AddRange(ExploreEitherSide(centers[centers.Count / 2], command.StartingLocation, requested.Location, detourRadius * 0.75));
            foreach (var center in centers.Distinct())
            {
                var found = await _localDiscoveryProvider.DiscoverForPlanningAsync(
                    command with { StartingLocation = center, SelectedPlace = null }, ct, 30);
                candidates.AddRange(found.Stops.Where(stop => WalkInterestPolicy.Allows(stop, command.Interests) && !SamePlace(stop, requested) &&
                    (!requested.IsDestination || (RouteMath.DistanceFromRouteMeters(stop.Location, geometry) <= detourRadius &&
                        RouteMath.DistanceMeters(stop.Location, geometry[0]) > RouteMath.DistanceFromRouteMeters(stop.Location, geometry) + 1 &&
                        RouteMath.DistanceMeters(stop.Location, geometry[^1]) > RouteMath.DistanceFromRouteMeters(stop.Location, geometry) + 1 &&
                        RouteMath.DistanceMeters(stop.Location, requested.Location) > 25))));
            }
        }
        var unique = new List<WalkStop>();
        foreach (var candidate in candidates)
            if (!unique.Any(stop => SamePlace(stop, candidate))) unique.Add(candidate);
        var selection = _storySelector?.Enabled == true && unique.Count > 0
            ? await _storySelector.SelectAsync(command with { StoryDestination = requested.Location }, unique, DesiredStopCount(command.AvailableMinutes) - 1, ct)
            : null;
        var pool = (selection?.Stops.Count > 0 ? selection.Stops.Concat(unique) : unique).DistinctBy(stop => stop.StopId).ToArray();
        var recommended = selection?.Stops.Select(stop => stop.StopId).ToHashSet() ?? [];
        var chosen = new List<WalkStop>();
        // Pick near evenly spaced positions before considering additional candidates.
        // This prevents the first search centre from consuming the entire stop budget.
        foreach (var center in CorridorCenters(direct.Coordinates, 400, 12))
        {
            var nearby = pool.Where(stop => CanAddCoffee(command, chosen, stop) && chosen.All(existing => !SamePlace(existing, stop) && RouteMath.DistanceMeters(existing.Location, stop.Location) >= 100))
                .Where(stop => RouteMath.DistanceMeters(center, stop.Location) <= 500)
                .OrderBy(stop => (int)(RouteMath.DistanceMeters(center, stop.Location) / 150))
                .ThenByDescending(stop => recommended.Contains(stop.StopId))
                .ThenBy(stop => RouteMath.DistanceMeters(center, stop.Location));
            var next = WalkInterestPolicy.TakeBalanced(nearby, 1, command.Interests, WalkInterestPolicy.Group,
                chosen.Select(WalkInterestPolicy.Group)).FirstOrDefault();
            if (next is not null && RouteMath.DistanceMeters(center, next.Location) <= 500)
                chosen.Add(next);
        }
        var timeForStops = Math.Max(0, command.AvailableMinutes - direct.DurationMinutes - requested.EstimatedVisitMinutes);
        var retained = new List<WalkStop>();
        // Spend the budget across the entire route even when early visits are expensive.
        var coverageOrder = chosen.OrderByDescending(stop => Math.Min(
            RouteMath.DistanceMeters(command.StartingLocation, stop.Location),
            RouteMath.DistanceMeters(requested.Location, stop.Location))).ToList();
        while (coverageOrder.Count > 0)
        {
            // Reserve a small walking detour allowance as well as the visit.
            var stop = retained.Count == 0 ? coverageOrder.MinBy(candidate => RouteMath.DistanceMeters(command.StartingLocation, candidate.Location))! : coverageOrder.MaxBy(candidate =>
                retained.Min(other => RouteMath.DistanceMeters(candidate.Location, other.Location)))!;
            coverageOrder.Remove(stop);
            var cost = Math.Max(1, stop.EstimatedVisitMinutes) + 3;
            if (cost > timeForStops) continue;
            retained.Add(stop);
            timeForStops -= cost;
        }
        IReadOnlyList<WalkStop> stops = requested.IsDestination
            ? Resequence(command.StartingLocation, retained.OrderBy(stop => ReferenceEquals(stop, chosen.FirstOrDefault()) && RouteMath.DistanceMeters(command.StartingLocation, stop.Location) <= 200 ? -1 : RouteMath.ProgressPercentage(stop.Location, direct)).ToArray())
            : CreateEfficientStopPlan(command, retained, retained.Count);
        if (requested.IsDestination)
            stops = Resequence(command.StartingLocation, stops.Append(requested).ToArray());
        else
            stops = CreateEfficientStopPlan(command, stops.Append(requested).ToArray(), stops.Count + 1);
        var route = stops.Count == 1 ? direct : await _routeProvider.CreateRouteAsync(command, stops, ct);
        while (stops.Count > 1 && route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes) > command.AvailableMinutes)
        {
            // Reduce evenly across the corridor; an explicit choice can never be trimmed.
            var optional = stops.Where(stop => !SamePlace(stop, requested)).ToArray();
            var keep = optional.Length <= 1 ? [] : optional.Where((_, index) => index % 2 == 0).ToArray();
            stops = requested.IsDestination
                ? Resequence(command.StartingLocation, keep.Append(requested).ToArray())
                : CreateEfficientStopPlan(command, keep.Append(requested).ToArray(), keep.Count() + 1);
            if (!stops.Any(stop => SamePlace(stop, requested))) stops = new[] { requested };
            route = stops.Count == 1 ? direct : await _routeProvider.CreateRouteAsync(command, stops, ct);
        }
        (stops, route) = await FillAvailableTimeAsync(command, stops, route, pool, ct, balanceInterests: true);
        var duration = route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes);
        EnsureSelectedPlaceRoute(route);
        var summary = requested.IsDestination ? $"Walk to {requested.Name}." : $"Walk via {requested.Name}.";
        summary += stops.Count > 1 ? " Includes discoveries matched to your walk preferences." : " No additional stops fit this route and time.";
        if (duration > command.AvailableMinutes)
            summary += " This route exceeds your requested time; review the estimate before starting.";
        summary += TimingSummary(command, route, stops);
        return new WalkSession(Guid.NewGuid().ToString("n"), command.StartingLocation, DateTimeOffset.UtcNow,
            command.AvailableMinutes, duration, route.DistanceMeters, summary, command.Interests,
            command.WalkingPace, command.AccessibilityPreferences, stops, route) { ProfileId = command.ProfileId, StopSelectionStatus = selection?.Status };
    }

    private static bool CanAddCoffee(CreateWalkCommand command, IEnumerable<WalkStop> chosen, WalkStop candidate) =>
        !WalkInterestPolicy.IsFood(candidate) || command.Interests.All(WalkInterestPolicy.IsFood) ||
        command.Interests.Any(i => WalkInterestPolicy.IsFood(i) &&
            !WalkInterestPolicy.IsCoffee(i)) || chosen.Count(WalkInterestPolicy.IsFood) <
            Math.Ceiling(DesiredStopCount(command.AvailableMinutes) / (double)Math.Max(1,
                command.Interests.Select(WalkInterestPolicy.Group).Distinct().Count()));

    private static IEnumerable<GeoLocation> ExploreEitherSide(GeoLocation center, GeoLocation start, GeoLocation end, double metres)
    {
        var north = end.Latitude - start.Latitude;
        var east = (end.Longitude - start.Longitude) * Math.Cos(center.Latitude * Math.PI / 180);
        var length = Math.Sqrt(north * north + east * east);
        var acrossNorth = length > 0 ? -east / length * metres : metres;
        var acrossEast = length > 0 ? north / length * metres : 0;
        yield return OffsetMeters(center, acrossNorth, acrossEast);
        yield return OffsetMeters(center, -acrossNorth, -acrossEast);
    }

    private static string TimingSummary(CreateWalkCommand command, WalkRoute route, IReadOnlyList<WalkStop> stops)
    {
        var visits = stops.Sum(stop => stop.EstimatedVisitMinutes);
        var total = route.DurationMinutes + visits;
        var estimate = $" About {total} min total: {route.DurationMinutes} min walking and {visits} min at stops.";
        return total < command.AvailableMinutes * 0.9
            ? estimate + $" This is shorter than your {command.AvailableMinutes}-minute request."
            : estimate;
    }

    private async Task<(IReadOnlyList<WalkStop>, WalkRoute)> FillAvailableTimeAsync(
        CreateWalkCommand command, IReadOnlyList<WalkStop> stops, WalkRoute route,
        IReadOnlyList<WalkStop> candidates, CancellationToken ct, bool balanceInterests = false)
    {
        var remaining = candidates.Where(candidate => !stops.Any(stop => SamePlace(candidate, stop)))
            .DistinctBy(candidate => candidate.StopId).ToList();
        // Estimate detours cheaply, then validate the best one with actual walking directions.
        // A rejected detour leaves the last usable route intact.
        for (var attempt = 0; attempt < 8 && remaining.Count > 0 && stops.Count < 12; attempt++)
        {
            var total = route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes);
            if (total >= command.AvailableMinutes * 0.9) break;
            var minutesPerMetre = route.DurationMinutes / Math.Max(1d, PlannedDistance(command.StartingLocation, stops));
            minutesPerMetre = Math.Clamp(minutesPerMetre, 0.01, 0.035);
            var eligible = remaining.Where(candidate => CanAddCoffee(command, stops, candidate)).ToArray();
            if (eligible.Length == 0) break;
            var options = eligible.Select(candidate =>
            {
                var bestIndex = 1;
                var bestDistance = double.MaxValue;
                var lastIndex = stops[^1].IsDestination ? stops.Count - 1 : stops.Count;
                var firstIndex = stops.Count == 1 || RouteMath.DistanceMeters(command.StartingLocation, candidate.Location)
                    < Math.Min(200, RouteMath.DistanceMeters(command.StartingLocation, stops[0].Location)) ? 0 : 1;
                for (var index = firstIndex; index <= lastIndex; index++)
                {
                    var previous = index == 0 ? command.StartingLocation : stops[index - 1].Location;
                    var extra = RouteMath.DistanceMeters(previous, candidate.Location);
                    if (index < stops.Count)
                        extra += RouteMath.DistanceMeters(candidate.Location, stops[index].Location)
                            - RouteMath.DistanceMeters(previous, stops[index].Location);
                    if (extra < bestDistance) { bestIndex = index; bestDistance = extra; }
                }
                return (candidate, bestIndex, minutes: bestDistance * minutesPerMetre + candidate.EstimatedVisitMinutes);
            });
            var ranked = options.OrderBy(option => Math.Abs(command.AvailableMinutes - total - option.minutes));
            var next = balanceInterests
                ? WalkInterestPolicy.TakeBalanced(ranked, 1, command.Interests, option => WalkInterestPolicy.Group(option.candidate),
                    stops.Select(WalkInterestPolicy.Group)).FirstOrDefault()
                : ranked.First();
            if (next.candidate is null) break;
            remaining.RemoveAll(candidate => SamePlace(candidate, next.candidate));
            var trial = stops.ToList();
            trial.Insert(next.bestIndex, next.candidate);
            var ordered = Resequence(command.StartingLocation, trial);
            var directions = await _routeProvider.CreateRouteAsync(command, ordered, ct);
            var newTotal = directions.DurationMinutes + ordered.Sum(stop => stop.EstimatedVisitMinutes);
            if (directions.Provider == route.Provider && newTotal > total && newTotal <= command.AvailableMinutes)
            {
                stops = ordered;
                route = directions;
            }
        }
        return (stops, route);
    }

    private static IReadOnlyList<GeoLocation> CorridorCenters(IReadOnlyList<GeoLocation> geometry,
        double spacing = 800, int maximum = 8)
    {
        if (geometry.Count < 2) return geometry;
        var lengths = geometry.Zip(geometry.Skip(1), RouteMath.DistanceMeters).ToArray();
        var total = lengths.Sum();
        var intervals = Math.Clamp((int)Math.Ceiling(total / spacing), 1, maximum - 1);
        var result = new List<GeoLocation> { geometry[0] };
        for (var n = 1; n <= intervals; n++)
        {
            var target = total * n / intervals;
            var before = 0d;
            for (var i = 0; i < lengths.Length; i++)
            {
                if (before + lengths[i] >= target || i == lengths.Length - 1)
                {
                    var ratio = lengths[i] == 0 ? 0 : Math.Clamp((target - before) / lengths[i], 0, 1);
                    result.Add(new GeoLocation(geometry[i].Latitude + (geometry[i + 1].Latitude - geometry[i].Latitude) * ratio,
                        geometry[i].Longitude + (geometry[i + 1].Longitude - geometry[i].Longitude) * ratio));
                    break;
                }
                before += lengths[i];
            }
        }
        return result;
    }

    private static bool SamePlace(WalkStop a, WalkStop b) =>
        a.StopId == b.StopId || (!string.IsNullOrEmpty(a.ProviderPlaceId) && a.ProviderPlaceId == b.ProviderPlaceId) ||
        (a.Name.Equals(b.Name, StringComparison.OrdinalIgnoreCase) && RouteMath.DistanceMeters(a.Location, b.Location) < 40);

    private void EnsureSelectedPlaceRoute(WalkRoute route)
    {
        if (_routeProvider.ProviderName != "Mock" && route.Provider == "Mock")
            throw new InvalidOperationException("Walking directions to that place are temporarily unavailable. Please try again.");
    }

    public static IReadOnlyList<WalkStop> CreateLocalFieldTestStops(GeoLocation startingLocation)
    {
        return CreateLocalWaypointStops(startingLocation);
    }

    public static IReadOnlyList<WalkStop> CreateLocalWaypointStops(GeoLocation startingLocation)
    {
        return new[]
        {
            new WalkStop(
                "local-field-test-start",
                1,
                "Starting Point",
                startingLocation,
                "Your selected starting area.",
                "You have arrived at the starting point. Take a moment to look around, check your surroundings, and let Rover settle into the walk.",
                "Starting Point",
                ContentType.History,
                ContentSource.RoverEditorial,
                3,
                0,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters),
            new WalkStop(
                "local-field-test-north",
                2,
                "Nearby Waypoint",
                OffsetMeters(startingLocation, 120, 0),
                "A short nearby waypoint to keep the walk moving.",
                "You have arrived at a nearby waypoint. Rover does not have a verified story for this exact spot yet, so use this pause to notice the road, landscape, buildings, and sounds around you.",
                "Waypoint",
                ContentType.History,
                ContentSource.RoverEditorial,
                4,
                120,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters),
            new WalkStop(
                "local-field-test-east",
                3,
                "Local Turn",
                OffsetMeters(startingLocation, 120, 120),
                "A nearby turn that gives the route a little shape.",
                "You have arrived at the local turn. This is a good moment for Rover to add live context when connected to conversation and web search.",
                "Waypoint",
                ContentType.PublicArt,
                ContentSource.RoverEditorial,
                4,
                120,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters),
            new WalkStop(
                "local-field-test-return",
                4,
                "Return Waypoint",
                OffsetMeters(startingLocation, 0, 120),
                "A final nearby waypoint before the route settles back.",
                "You have arrived at the return waypoint. Rover will keep using live places where they are available, and simple local waypoints where the area has limited indexed content.",
                "Waypoint",
                ContentType.History,
                ContentSource.LocalRecommendation,
                4,
                120,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters)
        };
    }

    private static GeoLocation OffsetMeters(GeoLocation origin, double northMeters, double eastMeters)
    {
        const double metersPerDegreeLatitude = 111_320d;
        var latitude = origin.Latitude + northMeters / metersPerDegreeLatitude;
        var longitude = origin.Longitude + eastMeters / (metersPerDegreeLatitude * Math.Cos(origin.Latitude * Math.PI / 180d));
        return new GeoLocation(latitude, longitude);
    }

    public static IReadOnlyList<WalkStop> CreateUnionSquareStops()
    {
        return new[]
        {
            new WalkStop(
                "union-square-plaza",
                1,
                "Union Square Plaza",
                new GeoLocation(37.7880, -122.4075),
                "The central plaza that gives the neighborhood its name.",
                "Start in the open plaza and look at how the square works as both civic room and retail crossroads.",
                "Landmark",
                ContentType.History,
                ContentSource.RoverEditorial,
                6,
                0,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters),
            new WalkStop(
                "dewey-monument",
                2,
                "Dewey Monument",
                new GeoLocation(37.7879, -122.4074),
                "A tall monument anchoring the middle of Union Square.",
                "The monument gives the plaza a formal center, but the real story is how people orbit it throughout the day.",
                "Public Art",
                ContentType.PublicArt,
                ContentSource.RoverEditorial,
                5,
                45,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters),
            new WalkStop(
                "maiden-lane",
                3,
                "Maiden Lane",
                new GeoLocation(37.7885, -122.4058),
                "A narrow pedestrian lane lined with boutiques and layered city history.",
                "Maiden Lane is a quick shift in scale: quieter, narrower, and easier to read on foot than from a car.",
                "Shopping",
                ContentType.Shopping,
                ContentSource.RoverEditorial,
                7,
                190,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters),
            new WalkStop(
                "vc-morris-gift-shop",
                4,
                "V. C. Morris Gift Shop",
                new GeoLocation(37.7882, -122.4055),
                "A Frank Lloyd Wright-designed storefront with a distinctive brick facade.",
                "Pause at the brick arch and notice the contrast between the modest exterior and the spiraling interior idea Wright explored here.",
                "Architecture",
                ContentType.Architecture,
                ContentSource.RoverEditorial,
                6,
                70,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters),
            new WalkStop(
                "local-cafe-corner",
                5,
                "Local Cafe Corner",
                new GeoLocation(37.7875, -122.4062),
                "A nearby independent coffee stop suited to a short walking break.",
                "This is a local recommendation, not Rover editorial history: use it as a practical pause before the last leg.",
                "Cafe",
                ContentType.FoodAndDrink,
                ContentSource.LocalRecommendation,
                8,
                130,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters),
            new WalkStop(
                "sponsored-gear-stop",
                6,
                "Sponsored Walking Gear Stop",
                new GeoLocation(37.7869, -122.4071),
                "A disclosed sponsored retail stop near the square.",
                "This sponsored stop is included as a clearly labeled commercial recommendation and is not Rover editorial content.",
                "Sponsored",
                ContentType.SponsoredRecommendation,
                ContentSource.Sponsored,
                5,
                145,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters,
                "Sponsored content: this stop is paid placement and is not Rover editorial content."),
            new WalkStop(
                "powell-street-cable-car-turnaround",
                7,
                "Powell Street Cable Car Turnaround",
                new GeoLocation(37.7847, -122.4077),
                "A lively transit landmark that closes the loop toward Market Street.",
                "End with the cable car turnaround, where the city turns transportation into public theater.",
                "Transit Landmark",
                ContentType.History,
                ContentSource.RoverEditorial,
                6,
                260,
                WalkGeofenceDefaults.StandardArrivalRadiusMeters)
        };
    }
}
