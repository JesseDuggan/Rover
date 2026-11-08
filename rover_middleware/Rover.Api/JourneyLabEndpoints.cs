using Rover.Application.Drives;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;
using Rover.Infrastructure.LocationIntelligence;

namespace Rover.Api;

public sealed record LabNearbyRequest(GeoLocation Location, string[] Interests);
public sealed record LabPlace(string Id, string Name, double Latitude, double Longitude, string Category,
    string? Attribution = null, string? SourceUrl = null, string? Address = null);
public sealed record LabPlanRequest(GeoLocation Start, GeoLocation? End, LabPlace[] Stops, bool Suggest,
    int Minutes, string[] Interests);
public sealed record LabDecision(string Name, string Reason);
public sealed record LabPlan(IReadOnlyList<LabPlace> Stops, IReadOnlyList<GeoLocation> Coordinates,
    int WalkingMinutes, int VisitMinutes, int DistanceMeters, string? StopSelectionStatus = null, IReadOnlyList<LabDecision>? Skipped = null);

public static class JourneyLabEndpoints
{
    public static void MapJourneyLab(this WebApplication app)
    {
        var group = app.MapGroup("/api/journey-lab");
        group.MapGet("/search", async (string query, GooglePlacesLocationContextProvider places, CancellationToken ct) =>
        {
            if (string.IsNullOrWhiteSpace(query) || query.Length > 256) return Results.BadRequest();
            var result = await places.SearchMapAsync(query.Trim(), ct);
            if (result.Places.Count == 0 && result.Warnings.Any(w => w != "Google Places returned no places."))
                return Results.Problem("Place search is unavailable. Try again.", statusCode: 503);
            return Results.Ok(new { stops = result.Places.Where(p => p.SourceReferences.Count > 0).Select(ToLabPlace) });
        });
        group.MapPost("/nearby", async (LabNearbyRequest request, GooglePlacesLocationContextProvider places, CancellationToken ct) =>
        {
            if (!ScenicDriveService.ValidLocation(request.Location) || !ValidInterests(request.Interests))
                return Results.BadRequest();
            var found = await places.GetContextAsync(new LocationContextQuery(request.Location, 400,
                null, null, [], request.Interests), ct);
            var stops = found.Places.Where(p => p.SourceReferences.Count > 0 &&
                    RouteMath.DistanceMeters(request.Location, p.Coordinates) <= 400 &&
                    !WalkInterestPolicy.IsTicketOffice(p.Name, p.Categories.FirstOrDefault() ?? ""))
                .OrderBy(p => RouteMath.DistanceMeters(request.Location, p.Coordinates))
                .DistinctBy(p => p.CanonicalId).Take(15)
                .Select(ToLabPlace);
            if (!found.Enabled || (found.Places.Count == 0 && found.Warnings.Count > 0))
                return Results.Problem("Place search is unavailable. Try again.", statusCode: 503);
            return Results.Ok(new { stops });
        });
        group.MapPost("/plan", async (LabPlanRequest request, IWalkPlanner planner, IWalkRouteProvider routes, CancellationToken ct) =>
        {
            if (!ValidPlan(request))
                return Results.Problem("Choose a start and valid stops or a destination, and 15 to 240 minutes.", statusCode: 400);
            try { return Results.Ok(await BuildAsync(request, planner, routes, ct)); }
            catch (InvalidOperationException) { return Results.Problem("Walking directions are unavailable for these points.", statusCode: 503); }
        });
    }

    private static LabPlace ToLabPlace(LocationPlace p) => new(p.CanonicalId, p.Name, p.Coordinates.Latitude,
        p.Coordinates.Longitude, p.Categories.FirstOrDefault() ?? "Place", p.SourceReferences[0].Attribution,
        p.SourceReferences[0].SourceUrl, p.Address);

    private static bool ValidInterests(string[]? values) =>
        values is { Length: <= 20 } && values.All(value => !string.IsNullOrWhiteSpace(value) && value.Length <= 80);

    public static bool ValidPlan(LabPlanRequest request) =>
        ScenicDriveService.ValidLocation(request.Start) && (request.End is null || ScenicDriveService.ValidLocation(request.End))
        && request.Minutes is >= 15 and <= 240 && ValidInterests(request.Interests)
        && request.Stops is { Length: <= 20 } && request.Stops.All(p => p is not null && !string.IsNullOrWhiteSpace(p.Id)
            && p.Id.Length <= 256 && !string.IsNullOrWhiteSpace(p.Name) && p.Name.Length <= 256
            && p.Category is { Length: <= 120 } && ScenicDriveService.ValidLocation(new(p.Latitude, p.Longitude)))
        && request.Stops.DistinctBy(p => p.Id).Count() == request.Stops.Length
        && (request.Suggest ? request.End is not null && request.Stops.Length == 0 : request.Stops.Length > 0 || request.End is not null);

    public static async Task<LabPlan> BuildAsync(LabPlanRequest request, IWalkPlanner planner, IWalkRouteProvider routes, CancellationToken ct)
    {
        var command = new CreateWalkCommand(request.Start, request.Minutes, request.Interests, WalkingPace.Standard, []);
        var end = request.End is null ? null : new WalkStop("lab-end", 1, "Finish", request.End, "", "", "Destination",
            ContentType.History, ContentSource.LocalRecommendation, 0, 0, WalkGeofenceDefaults.StandardArrivalRadiusMeters) { IsDestination = true };
        if (request.Suggest && end is not null)
        {
            var decisions = new Dictionary<string, LabDecision>();
            var session = await planner.PlanToPlaceAsync(command with {
                LimitLabDetours = true,
                RecordLabDecision = (stop, reason) => decisions[stop.StopId] = new(stop.Name, reason)
            }, end, ct);
            foreach (var stop in session.Stops) decisions.Remove(stop.StopId);
            var suggestions = session.Stops.Where(s => !s.IsDestination).Select(s => new LabPlace(s.StopId, s.Name,
                s.Location.Latitude, s.Location.Longitude, s.Category, string.Join(", ", s.RequiredAttribution), s.SourceUrl)).ToArray();
            return Describe(suggestions, session.Route, session.Stops.Sum(s => s.EstimatedVisitMinutes), routes)
                with { StopSelectionStatus = session.StopSelectionStatus, Skipped = decisions.Values.ToArray() };
        }

        var visits = request.Stops.Select((p, i) => new WalkStop(p.Id, i + 1, p.Name, new(p.Latitude, p.Longitude),
            "", "", p.Category, ContentType.History, ContentSource.LocalRecommendation, WalkInterestPolicy.IsFood(p.Category) ? 5 : 2,
            0, WalkGeofenceDefaults.StandardArrivalRadiusMeters)).ToList();
        if (end is not null && (visits.Count == 0 || visits[^1].Location != end.Location)) visits.Add(end);
        var route = await routes.CreateRouteAsync(command, visits, ct);
        return Describe(request.Stops, route, visits.Sum(s => s.EstimatedVisitMinutes), routes);
    }

    private static LabPlan Describe(IReadOnlyList<LabPlace> stops, WalkRoute route, int visits, IWalkRouteProvider provider)
    {
        if (route.Provider == "Mock" && provider.ProviderName != "Mock")
            throw new InvalidOperationException("Walking directions are unavailable.");
        return new(stops, route.Coordinates, route.DurationMinutes, visits, route.DistanceMeters);
    }
}
