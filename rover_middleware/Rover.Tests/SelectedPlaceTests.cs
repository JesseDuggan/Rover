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

    public static async Task Planning()
    {
        var discovery = new Discovery();
        var planner = new MockWalkPlanner(new MockWalkRouteProvider(), discovery,
            placeSearch: new WalkPlaceSearchService(new[] { new Search() }));
        var walk = await planner.PlanWalkAsync(Command(), default);
        Check(walk.Stops.Count > 1 && walk.Stops[^1].IsDestination, "Include corridor stops and finish at destination.");
        Check(walk.Route.Coordinates[^1] == walk.Stops[^1].Location, "Walking route ends at chosen place.");
        Check(walk.Stops.All(stop => stop.StopId != "far"), "Exclude stops outside the corridor.");
        Check(discovery.Commands.Count is > 0 and <= 3, "Bound corridor searches.");
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
                Stop("monument", new(52.015, 4.0225)), Stop("far", new(52.2, 4.3)) });
        }
        private static WalkStop Stop(string id, GeoLocation location) => new(id, 1, id, location, "Sourced history.", "Sourced history.",
            "History", ContentType.History, ContentSource.LocalRecommendation, 3, 0, 30);
    }
    private sealed class Nearby : INearbyDiscoveryProvider
    {
        public Task<IReadOnlyList<NearbyDiscovery>> FindAsync(WalkSession session, GeoLocation currentLocation,
            string? interest, IReadOnlyCollection<string> dismissedDiscoveryIds, CancellationToken ct) =>
            Task.FromResult<IReadOnlyList<NearbyDiscovery>>(Array.Empty<NearbyDiscovery>());
    }
}
