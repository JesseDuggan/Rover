using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Walks;

public sealed class MockWalkPlanner : IWalkPlanner
{
    private readonly IWalkRouteProvider _routeProvider;
    private readonly ILocalDiscoveryProvider _localDiscoveryProvider;
    private readonly IStoryLedStopSelector? _storySelector;

    public MockWalkPlanner()
        : this(new MockWalkRouteProvider(), new NoOpLocalDiscoveryProvider())
    {
    }

    public MockWalkPlanner(IWalkRouteProvider routeProvider, ILocalDiscoveryProvider? localDiscoveryProvider = null,
        IStoryLedStopSelector? storySelector = null)
    {
        _routeProvider = routeProvider;
        _localDiscoveryProvider = localDiscoveryProvider ?? new NoOpLocalDiscoveryProvider();
        _storySelector = storySelector;
    }

    public async Task<WalkSession> PlanWalkAsync(CreateWalkCommand command, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var storyPlanning = _storySelector?.Enabled == true;
        var isUnionSquareStart = !storyPlanning && RouteMath.DistanceMeters(command.StartingLocation, new GeoLocation(37.7880, -122.4075)) < 5_000;
        var desiredStops = DesiredStopCount(command.AvailableMinutes);
        var discoveredStops = isUnionSquareStart
            ? Array.Empty<WalkStop>()
            : await _localDiscoveryProvider.FindCandidateStopsAsync(command, cancellationToken, storyPlanning ? 30 : Math.Max(desiredStops * 2, 12));
        var selection = storyPlanning
            ? await _storySelector!.SelectAsync(command, discoveredStops, desiredStops, cancellationToken)
            : null;
        var stops = isUnionSquareStart
            ? CreateUnionSquareStops()
            : selection?.Stops.Count >= 2
            ? CreateEfficientStopPlan(command, selection.Stops, selection.Stops.Count)
            : discoveredStops.Count >= 2
            ? CreateEfficientStopPlan(command, discoveredStops, desiredStops)
            : CreateLocalWaypointStops(command.StartingLocation);
        var route = await _routeProvider.CreateRouteAsync(command, stops, cancellationToken);
        // One bounded reroute may reduce an over-budget selection. Never fabricate an ETA.
        if (selection?.Stops.Count > 2 && route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes) > command.AvailableMinutes)
        {
            var total = route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes);
            var count = Math.Clamp((int)Math.Floor(stops.Count * command.AvailableMinutes / (double)total), 2, stops.Count - 1);
            var retained = selection.Stops.Take(count).ToArray();
            stops = CreateEfficientStopPlan(command, retained, retained.Length);
            route = await _routeProvider.CreateRouteAsync(command, stops, cancellationToken);
        }
        var estimatedDurationMinutes = storyPlanning
            ? route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes)
            : Math.Min(command.AvailableMinutes, route.DurationMinutes + stops.Sum(stop => stop.EstimatedVisitMinutes));
        var estimatedDistanceMeters = route.DistanceMeters;
        var summary = isUnionSquareStart
            ? "A compact Union Square loop with architecture, public art, shopping history, a local cafe recommendation, and one clearly disclosed sponsored stop."
            : discoveredStops.Count >= 2
            ? "A live local walk using nearby places and walking-route geometry."
            : "A short local walk generated around your selected starting area.";
        if (selection is not null)
        {
            summary += selection.Stops.Count >= 2
                ? $" Story-led planning: {selection.Status}; {stops.Count} stops retained."
                : $" Story-led planning fallback: {selection.Status}.";
            if (estimatedDurationMinutes > command.AvailableMinutes)
                summary += " This route exceeds your requested time; review the estimate before starting.";
        }

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
            route);

        return session;
    }

    private static int DesiredStopCount(int availableMinutes)
    {
        return Math.Clamp((int)Math.Round(availableMinutes / 8d), 3, 12);
    }

    private static IReadOnlyList<WalkStop> CreateEfficientStopPlan(
        CreateWalkCommand command,
        IReadOnlyList<WalkStop> candidates,
        int desiredStops)
    {
        var uniqueCandidates = candidates
            .GroupBy(stop => string.IsNullOrWhiteSpace(stop.StopId) ? stop.Name : stop.StopId, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderBy(stop => RouteMath.DistanceMeters(command.StartingLocation, stop.Location)).First())
            .ToArray();
        var selected = SelectGeographicallyVariedStops(
            command.StartingLocation,
            uniqueCandidates,
            Math.Clamp(desiredStops, 2, 12));

        if (selected.Length <= 2)
        {
            return Resequence(command.StartingLocation, selected);
        }

        var ordered = new List<WalkStop> { selected.OrderBy(stop => RouteMath.DistanceMeters(command.StartingLocation, stop.Location)).First() };
        foreach (var stop in selected.Where(stop => !ReferenceEquals(stop, ordered[0])))
        {
            var bestIndex = 0;
            var bestDistance = double.MaxValue;
            for (var index = 0; index <= ordered.Count; index++)
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
                stop.RequiredAttribution));
            previous = stop.Location;
        }

        return resequenced;
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
                ContentType.FoodAndDrink,
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
                "Food and Drink",
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
