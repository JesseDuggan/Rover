using Rover.Application.Adaptations;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;
using Rover.Infrastructure.Adaptations;
using Rover.Infrastructure.Walks;

internal static class SelectedPlaceTests
{
    private static readonly GeoLocation Start = new(52, 4);
    private static CreateWalkCommand Command(bool destination = true, int minutes = 60) =>
        new(Start, minutes, new[] { "history", "architecture" }, WalkingPace.Standard,
            new[] { AccessibilityPreference.AvoidStairs })
        { SelectedPlace = new("Hotel", "target", destination) };

    public static async Task Selection()
    {
        var service = new WalkPlaceSearchService(new[] { new Search() });
        var result = await service.SearchAsync("Hotel", Start, default);
        Check(result.Places.Count == 2, "Return ambiguous matches for the user to choose.");
        var stop = await service.ResolveAsync(new("Hotel", "other", true), Start, default);
        Check(stop.Name == "Other Hotel" && stop.ProviderPlaceId == "other", "Use the selected identity, not the first result.");
        Check(stop.IsDestination && stop.RequiredAttribution.Contains("Test provider"), "Keep role and attribution.");
        try { await service.ResolveAsync(new("Hotel", "missing"), Start, default); throw new Exception("Unknown ID accepted."); }
        catch (InvalidOperationException) { }
        Check(!WalkPlaceSearchService.IsValid(new("", "target")), "Reject missing query.");
        var partial = await new WalkPlaceSearchService(new ICandidateObservationSearchProvider[] {
            new FailingSearch(), new Search() }).SearchAsync("Hotel", Start, default);
        Check(partial.Places.Count == 2 && partial.Warnings.Count == 1,
            "One failed provider cannot hide valid matches from another.");
    }

    public static async Task Direction()
    {
        var routes = new MockWalkRouteProvider();
        var planner = new MockWalkPlanner(routes, new Discovery(),
            placeSearch: new WalkPlaceSearchService(new[] { new Search() }));
        var walk = await planner.PlanWalkAsync(Command(), default);
        var clock = new DirectionClock(DateTimeOffset.UtcNow);
        walk.Start(clock.Now.AddMinutes(-50));
        var sessions = new InMemoryWalkSessionRepository();
        await sessions.AddAsync(walk, default);
        var ahead = new NearbyDiscovery("ahead", "Historic house ahead", "History", new(52.001, 4),
            "Sourced history", 2, 110, 2, ContentSource.LocalRecommendation, null, null, new[] { "history" });
        var options = new[] {
            ahead,
            ahead with { DiscoveryId = "behind", Location = new(51.999, 4) },
            ahead with { DiscoveryId = "sideways", Location = new(52, 4.003) },
            ahead with { DiscoveryId = "food", Name = "Cafe", Category = "Cafe" },
            ahead with { DiscoveryId = "paid", SponsoredDisclosure = "Paid" },
            ahead with { DiscoveryId = "too-far", Location = new(52.03, 4) },
            ahead with { DiscoveryId = "stairs", AccessibilityLimitations = "Stairs" },
        };
        var service = new WalkAdaptationService(sessions, new InMemoryWalkAdaptationRepository(),
            new Nearby(options), routes, clock);
        var command = new WalkAdaptationCommand(Start, walk.RouteRevision, WalkAdaptationType.FollowDirection,
            60, null, null, null, Array.Empty<string>()) { HeadingDegrees = 0 };
        var originalIds = walk.Stops.Select(stop => stop.StopId).ToArray();
        var originalRoute = walk.Route;
        var proposal = await service.EvaluateAsync(walk.WalkSessionId, command, default);
        Check(proposal.ProposedStops.Select(stop => stop.StopId).SequenceEqual(new[] { "ahead" }),
            "Only matching accessible places ahead within the remaining budget are proposed.");
        Check(proposal.EstimatedNewTotalMinutes <= 10, "Use remaining time, not the original sixty minutes.");
        Check(walk.Route == originalRoute && walk.Stops.Select(stop => stop.StopId).SequenceEqual(originalIds),
            "Evaluating a direction must not change the active walk.");
        await service.RejectAsync(walk.WalkSessionId, proposal.AdaptationId, default);
        Check(walk.Route == originalRoute, "Declining keeps the old route.");
        foreach (var heading in new double?[] { null, double.NaN, -1, 360 })
        {
            try {
                await service.EvaluateAsync(walk.WalkSessionId, command with { HeadingDegrees = heading }, default);
                throw new Exception("Invalid heading accepted.");
            } catch (InvalidOperationException) { }
        }
        try {
            await service.EvaluateAsync(walk.WalkSessionId, command with { AvailableMinutes = 1 }, default);
            throw new Exception("No-time route accepted.");
        } catch (InvalidOperationException) { }
        var fresh = await service.EvaluateAsync(walk.WalkSessionId, command, default);
        clock.Now = clock.Now.AddMinutes(9);
        try {
            await service.AcceptAsync(walk.WalkSessionId, fresh.AdaptationId, walk.RouteRevision, default);
            throw new Exception("An over-budget old proposal was accepted.");
        } catch (InvalidOperationException) { }
        Check(walk.Route == originalRoute, "A proposal that no longer fits time cannot mutate the walk.");
        clock.Now = clock.Now.AddMinutes(-9);
        var updated = await service.AcceptAsync(walk.WalkSessionId, fresh.AdaptationId, walk.RouteRevision, default);
        Check(updated.Route.Coordinates[^1] == ahead.Location && updated.Stops.All(stop => stop.ProviderPlaceId != "target"),
            "Accepting changes the endpoint instead of pulling the walker back.");
        Check(updated.Stops[^1].IsDestination, "The new endpoint replaces the old destination.");
        var rejoin = await service.EvaluateAsync(walk.WalkSessionId, command with {
            RequestedType = WalkAdaptationType.RejoinRoute, RouteRevision = updated.RouteRevision }, default);
        Check(rejoin.ProposedStops[^1].Location == ahead.Location, "Later rejoining keeps the new destination.");
        Check(!updated.TrackingState.IsOffRoute && updated.TrackingState.RouteProgressPercentage == 0,
            "Reset tracking for the accepted route.");
        var unavailable = new WalkAdaptationService(sessions, new InMemoryWalkAdaptationRepository(),
            new Nearby(Array.Empty<NearbyDiscovery>()), routes, TimeProvider.System);
        try {
            await unavailable.EvaluateAsync(walk.WalkSessionId, command with { RouteRevision = updated.RouteRevision }, default);
            throw new Exception("Empty options accepted.");
        } catch (InvalidOperationException) { }
    }

    public static async Task Planning()
    {
        var discovery = new Discovery();
        var planner = new MockWalkPlanner(new MockWalkRouteProvider(), discovery,
            placeSearch: new WalkPlaceSearchService(new[] { new Search() }));
        var walk = await planner.PlanWalkAsync(Command(), default);
        Check(walk.Stops.Count > 1 && walk.Stops[^1].IsDestination, "Include corridor stops and finish at destination.");
        Check(walk.Route.Coordinates[^1] == walk.Stops[^1].Location, "Walking route ends at chosen place.");
        Check(walk.Stops.All(stop => stop.StopId != "far"), "Exclude stops outside the corridor.");
        Check(discovery.Commands.Count is > 0 and <= 8, "Bound corridor searches.");
        Check(walk.Stops.All(stop => stop.StopId != "cafe"), "Do not add food when food is not selected.");
        Check(walk.Stops.Any(stop => stop.StopId == "museum") && walk.Stops.Any(stop => stop.StopId == "monument"),
            "Include useful discoveries near both halves of the destination corridor.");
        Check(discovery.Commands.All(command => command.Interests.SequenceEqual(Command().Interests) &&
            command.AccessibilityPreferences.SequenceEqual(Command().AccessibilityPreferences)), "Preserve interests and accessibility.");
        var shortWalk = await planner.PlanWalkAsync(Command(minutes: 15), default);
        Check(shortWalk.Stops.Any(stop => stop.ProviderPlaceId == "target"), "Never trim an explicit endpoint.");
        Check(shortWalk.EstimatedDurationMinutes >= shortWalk.Route.DurationMinutes, "Report real duration, not a capped estimate.");
        var via = await planner.PlanWalkAsync(Command(destination: false), default);
        Check(via.Stops.Count(stop => stop.ProviderPlaceId == "target") == 1 && via.Stops.All(stop => !stop.IsDestination),
            "Selected waypoint appears once without becoming a pinned endpoint.");
    }

    public static async Task Adaptation()
    {
        var places = new WalkPlaceSearchService(new[] { new Search() });
        var routes = new MockWalkRouteProvider();
        var planner = new MockWalkPlanner(routes, new Discovery(), placeSearch: places);
        var walk = await planner.PlanWalkAsync(Command(), default);
        var sessions = new InMemoryWalkSessionRepository();
        await sessions.AddAsync(walk, default);
        var service = new WalkAdaptationService(sessions, new InMemoryWalkAdaptationRepository(),
            new Nearby(), routes, TimeProvider.System, placeSearch: places, planner: planner);
        var replacement = new NearbyDiscovery("replacement", "Historic house", "History", new(52.007, 4.0105),
            "Sourced history", 1, 50, 2, ContentSource.LocalRecommendation, null, null, new[] { "history" });
        var replacing = new WalkAdaptationService(sessions, new InMemoryWalkAdaptationRepository(),
            new Nearby(new[] {
                replacement with { DiscoveryId = "food", Category = "Cafe", Name = "McCafe" },
                replacement with { DiscoveryId = "behind", Location = new(51.999, 3.9985) },
                replacement with { DiscoveryId = walk.NextStop!.StopId }, replacement }), routes, TimeProvider.System);
        var skipCommand = new WalkAdaptationCommand(Start, walk.RouteRevision, WalkAdaptationType.SkipStop,
            60, null, null, null, Array.Empty<string>());
        var skip = await replacing.EvaluateAsync(walk.WalkSessionId, skipCommand, default);
        Check(skip.ProposedStops.Any(stop => stop.StopId == "replacement"), "Replace with a matching place ahead.");
        Check(skip.ProposedStops.All(stop => stop.StopId != "food" && stop.StopId != "behind" && stop.StopId != walk.NextStop.StopId),
            "Exclude food, backward stops and the skipped place.");
        Check(skip.ProposedStops[^1].IsDestination && skip.EstimatedNewTotalMinutes <= 60,
            "Replacement preserves destination and remaining time budget.");
        var noTime = await replacing.EvaluateAsync(walk.WalkSessionId, skipCommand with { AvailableMinutes = 1 }, default);
        Check(noTime.ProposedStops.All(stop => stop.StopId != "replacement"), "Never add a replacement outside the time budget.");
        foreach (var detour in new[] { 5, 6 })
        {
            var bounded = new WalkAdaptationService(sessions, new InMemoryWalkAdaptationRepository(),
                new Nearby(new[] { replacement }), new DetourRoutes(detour), TimeProvider.System);
            var result = await bounded.EvaluateAsync(walk.WalkSessionId, skipCommand with { AvailableMinutes = 90 }, default);
            Check(result.ProposedStops.Any(stop => stop.StopId == "replacement") == (detour == 5),
                "Allow five extra walking minutes, but reject six even with spare time.");
        }
        Check(walk.Stops.Any(stop => stop.StopId == walk.NextStop.StopId), "Skip proposals do not mutate the walk.");
        var add = new WalkAdaptationCommand(Start, walk.RouteRevision, WalkAdaptationType.AddDiscovery,
            60, null, null, null, Array.Empty<string>()) { SelectedPlace = new("Hotel", "other") };
        var proposal = await service.EvaluateAsync(walk.WalkSessionId, add, default);
        Check(walk.Stops.All(stop => stop.ProviderPlaceId != "other"), "Do not change active walk before confirmation.");
        Check(proposal.ProposedStops[^1].IsDestination, "Insert before the endpoint.");
        var updated = await service.AcceptAsync(walk.WalkSessionId, proposal.AdaptationId, walk.RouteRevision, default);
        Check(updated.Stops[^1].IsDestination && updated.Stops[^1].ProviderPlaceId == "target", "Preserve destination and evidence when renumbering.");
        var shorten = await service.EvaluateAsync(walk.WalkSessionId, add with {
            RouteRevision = updated.RouteRevision, RequestedType = WalkAdaptationType.ShortenWalk, SelectedPlace = null }, default);
        Check(shorten.ProposedStops[^1].IsDestination, "Shortening cannot remove the endpoint.");
        var change = await service.EvaluateAsync(walk.WalkSessionId, add with {
            RouteRevision = updated.RouteRevision, RequestedType = WalkAdaptationType.SetDestination,
            SelectedPlace = new("Hotel", "other", true) }, default);
        Check(change.ProposedStops[^1].ProviderPlaceId == "other" && change.ProposedStops.Count(stop => stop.IsDestination) == 1,
            "Destination change creates an interest-aware replacement route.");
        updated.Stops.Single(stop => stop.ProviderPlaceId == "other").MarkArrived(DateTimeOffset.UtcNow);
        var returnVisit = await service.EvaluateAsync(walk.WalkSessionId, add with {
            RouteRevision = updated.RouteRevision, RequestedType = WalkAdaptationType.SetDestination,
            SelectedPlace = new("Hotel", "other", true) }, default);
        var returning = await service.AcceptAsync(walk.WalkSessionId, returnVisit.AdaptationId, updated.RouteRevision, default);
        Check(returning.Stops[^1].IsDestination && !returning.Stops[^1].Visited &&
            returning.Stops[^1].ProviderPlaceId == "other", "A previously visited destination remains a new pending visit.");
        Check(returning.Stops.Select(stop => stop.StopId).Distinct().Count() == returning.Stops.Count,
            "Separate visits cannot share stop IDs.");
        Check(returning.TrackingState.EstimatedMinutesRemaining == returning.Route.DurationMinutes +
            returning.Stops.Where(stop => !stop.Visited).Sum(stop => stop.EstimatedVisitMinutes),
            "Remaining-route estimates must not subtract visits completed before the route change.");
        var shortOriginal = await planner.PlanWalkAsync(Command(minutes: 15), default);
        await sessions.AddAsync(shortOriginal, default);
        var longer = await service.EvaluateAsync(shortOriginal.WalkSessionId, add with {
            RouteRevision = shortOriginal.RouteRevision, RequestedType = WalkAdaptationType.SetDestination,
            AvailableMinutes = 60, SelectedPlace = new("Hotel", "target", true) }, default);
        var acceptedLonger = await service.AcceptAsync(shortOriginal.WalkSessionId,
            longer.AdaptationId, shortOriginal.RouteRevision, default);
        Check(longer.EstimatedNewTotalMinutes > shortOriginal.AvailableMinutes &&
            acceptedLonger.EstimatedDurationMinutes == longer.EstimatedNewTotalMinutes,
            "Accepted routes must not cap their duration at the original budget.");
        try { await service.EvaluateAsync(walk.WalkSessionId, add, default); throw new Exception("Stale revision accepted."); }
        catch (WalkLifecycleException) { }
    }

    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class FailingSearch : ICandidateObservationSearchProvider
    {
        public Task<CandidateObservationSearchResult> SearchAsync(CandidateObservationQuery query, CancellationToken ct) =>
            throw new HttpRequestException("Unavailable");
    }
    private sealed class Search : ICandidateObservationSearchProvider
    {
        public Task<CandidateObservationSearchResult> SearchAsync(CandidateObservationQuery query, CancellationToken ct) =>
            Task.FromResult(new CandidateObservationSearchResult("Test", new[] {
                Place("target", "Target Hotel", new(52.02, 4.03)), Place("other", "Other Hotel", new(52.01, 4.015))
            }, Array.Empty<string>()));
        private static LocationPlace Place(string id, string name, GeoLocation location) =>
            new(id, name, location, "Test address", new[] { "Hotel" }, "Verified place description.",
                Array.Empty<LocationFact>(), new[] { new LocationSource("Test", id, "https://example.org/place", "Test provider",
                    null, DateTimeOffset.UtcNow, 1) }, new Dictionary<string, string>(), null, null, null, null, 1, 1,
                Array.Empty<string>(), Array.Empty<LocationImageReference>(), null, null, DateTimeOffset.UtcNow);
    }
    private sealed class Discovery : ILocalDiscoveryProvider
    {
        public List<CreateWalkCommand> Commands { get; } = new();
        public Task<IReadOnlyList<WalkStop>> FindStopsAsync(CreateWalkCommand command, CancellationToken ct) =>
            FindCandidateStopsAsync(command, ct);
        public Task<IReadOnlyList<WalkStop>> FindCandidateStopsAsync(CreateWalkCommand command, CancellationToken ct, int maximumStops = 30)
        {
            Commands.Add(command);
            return Task.FromResult<IReadOnlyList<WalkStop>>(new[] { Stop("museum", new(52.005, 4.0075)),
                Stop("monument", new(52.015, 4.0225)), Stop("far", new(52.2, 4.3)),
                new WalkStop("cafe", 1, "McCafe", new(52.01, 4.015), "Coffee", "Coffee", "Cafe",
                    ContentType.FoodAndDrink, ContentSource.LocalRecommendation, 3, 0, 30) });
        }
        private static WalkStop Stop(string id, GeoLocation location) => new(id, 1, id, location, "Sourced history.", "Sourced history.",
            "History", ContentType.History, ContentSource.LocalRecommendation, 3, 0, 30);
    }
    private sealed class DirectionClock(DateTimeOffset now) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = now;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Nearby(IReadOnlyList<NearbyDiscovery>? options = null) : INearbyDiscoveryProvider
    {
        public Task<IReadOnlyList<NearbyDiscovery>> FindAsync(WalkSession session, GeoLocation currentLocation,
            string? interest, IReadOnlyCollection<string> dismissedDiscoveryIds, CancellationToken ct) =>
            Task.FromResult<IReadOnlyList<NearbyDiscovery>>(options ?? Array.Empty<NearbyDiscovery>());
    }
    private sealed class DetourRoutes(int addedMinutes) : IWalkRouteProvider
    {
        public string ProviderName => "Mock";
        public async Task<WalkRoute> CreateRouteAsync(CreateWalkCommand command, IReadOnlyList<WalkStop> stops, CancellationToken ct)
        {
            var route = await new MockWalkRouteProvider().CreateRouteAsync(command, stops, ct);
            return new(route.RouteId, route.Provider, route.Version, route.GeneratedAtUtc, route.Coordinates, route.Bounds,
                route.DistanceMeters, 20 + (stops.Any(stop => stop.StopId == "replacement") ? addedMinutes : 0), route.Maneuvers);
        }
    }
}
