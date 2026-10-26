using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Drives;

public sealed record DriveRequest(GeoLocation Origin, WalkPlaceSelection Destination,
    bool ReturnToStart, int AvailableMinutes, int MinutesPerStop, IReadOnlyList<string> Interests)
{
    public DrivePreferences Preferences { get; init; } = new();
    public int MaxOptionalStops { get; init; } = 2;
}
public sealed record DrivePreferences(bool PreferLocalRoads = false, bool AvoidTolls = false,
    int MaxDetourMinutes = 15, bool IncludeRestStops = false, bool IncludeChargingStops = false);
public sealed record DrivePlace(string PlaceId, string Name, string? Address, GeoLocation Location, string Attribution);
public sealed record DrivePlaceResults(IReadOnlyList<DrivePlace> Places, IReadOnlyList<string> Warnings);
public sealed record DrivingRoute(int DrivingMinutes, int DistanceMeters, IReadOnlyList<GeoLocation> Geometry);
public sealed record DrivePlan(GeoLocation Origin, DrivePlace Destination, bool ReturnToStart,
    IReadOnlyList<DrivePlace> Stops, DrivingRoute Route, int StopMinutes, int BufferMinutes,
    int TotalMinutes, int AvailableMinutes, bool FitsBudget, IReadOnlyList<string> Warnings)
{
    public DrivePreferences Preferences { get; init; } = new();
}
public interface IDrivingRouteProvider
{
    Task<DrivingRoute> RouteAsync(GeoLocation origin, IReadOnlyList<GeoLocation> visits, CancellationToken ct, DrivePreferences? preferences = null);
}
public sealed class DrivingUnavailableException(string message) : Exception(message);

public sealed class ScenicDriveService(
    IEnumerable<ICandidateObservationSearchProvider> providers, IDrivingRouteProvider routes)
{
    public static readonly string[] AllowedInterests = DriveInterestCatalog.Queries.Keys.ToArray();
    public static bool ValidLocation(GeoLocation? value) => value is not null &&
        double.IsFinite(value.Latitude) && double.IsFinite(value.Longitude) &&
        Math.Abs(value.Latitude) <= 90 && Math.Abs(value.Longitude) <= 180;
    public static bool ValidRequest(DriveRequest? request) => request is not null &&
        ValidLocation(request.Origin) && request.Destination is not null &&
        WalkPlaceSearchService.IsValid(request.Destination) &&
        request.AvailableMinutes is >= 30 and <= 720 && request.MinutesPerStop is >= 5 and <= 60 &&
        request.Interests is { Count: <= 60 } && request.Interests.All(i => i is not null && AllowedInterests.Contains(i)) &&
        request.Preferences is not null && request.Preferences.MaxDetourMinutes is >= 5 and <= 60 &&
        request.MaxOptionalStops is >= 1 and <= 6;

    public Task<DrivePlaceResults> SearchAsync(string query, GeoLocation origin, CancellationToken ct) =>
        SearchWithinAsync(query, origin, 1_000_000, ct);

    private async Task<DrivePlaceResults> SearchWithinAsync(string query, GeoLocation origin, int radius, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(query) || query.Length > 256 || !ValidLocation(origin))
            throw new ArgumentException("Enter a destination and allow access to your current location.");
        var places = new List<DrivePlace>();
        var warnings = new List<string>();
        foreach (var provider in providers)
        {
            try
            {
                var found = await provider.SearchAsync(new(query.Trim(), origin, null, null, radius, null, []), ct);
                warnings.AddRange(found.Warnings.Where(w => !w.Contains("not configured", StringComparison.OrdinalIgnoreCase)));
                places.AddRange(found.Places.Where(p => p.SourceReferences.Count > 0 &&
                    ValidLocation(p.Coordinates) && RouteMath.DistanceMeters(origin, p.Coordinates) <= radius)
                    .Select(p => new DrivePlace(p.CanonicalId, p.Name, p.Address, p.Coordinates,
                        string.Join(", ", p.SourceReferences.Select(s => s.Attribution).Distinct()))));
            }
            catch (Exception e) when (e is HttpRequestException or JsonException ||
                e is OperationCanceledException && !ct.IsCancellationRequested)
            {
                warnings.Add("A place search provider is temporarily unavailable.");
            }
        }
        return new(places.DistinctBy(p => p.PlaceId).Take(10).ToArray(), warnings.Distinct().ToArray());
    }

    public async Task<DrivePlan> PlanAsync(DriveRequest request, CancellationToken ct)
    {
        if (!ValidRequest(request)) throw new ArgumentException("Choose a destination, 30-720 minutes, and 5-60 minutes per stop.");
        var search = await SearchAsync(request.Destination.Query, request.Origin, ct);
        var destination = search.Places.FirstOrDefault(p => p.PlaceId == request.Destination.PlaceId)
            ?? throw new ArgumentException("That destination could not be verified. Search again and select a result.");
        if (RouteMath.DistanceMeters(request.Origin, destination.Location) < 100)
            throw new ArgumentException("Choose a destination at least 100 metres from your starting point.");
        var warnings = search.Warnings.ToList();
        warnings.Add("Estimates include stop time and a travel buffer. Traffic, opening hours and parking can change.");
        var preferences = request.Preferences;
        if (preferences.PreferLocalRoads || preferences.AvoidTolls)
            warnings.Add("Road preferences are requests, not guarantees. Check the route in Google Maps before departing.");
        if (preferences.IncludeChargingStops)
            warnings.Add("Check charger compatibility, availability and charging time before visiting.");
        var outbound = await routes.RouteAsync(request.Origin, [destination.Location], ct, preferences);
        var accepted = new List<DrivePlace>();
        List<GeoLocation> Visits(IEnumerable<DrivePlace> stops) => stops.Select(p => p.Location)
            .Append(destination.Location).Concat(request.ReturnToStart ? [request.Origin] : Array.Empty<GeoLocation>()).ToList();
        var route = request.ReturnToStart
            ? await routes.RouteAsync(request.Origin, Visits(accepted), ct, preferences) : outbound;
        int Buffer(DrivingRoute r) => Math.Max(5, (int)Math.Ceiling(r.DrivingMinutes * .15));
        int Total(DrivingRoute r, int count) => r.DrivingMinutes + Buffer(r) + (count + 1) * request.MinutesPerStop;
        var queries = request.Interests.Distinct().Select(i => DriveInterestCatalog.Queries[i]).Distinct().ToList();
        if (preferences.IncludeRestStops) queries.Add("rest area");
        if (preferences.IncludeChargingStops) queries.Add("electric vehicle charging station");
        if (Total(route, 0) + request.MinutesPerStop <= request.AvailableMinutes && queries.Count > 0)
        {
            // Search every selected topic, spread over the route. Limit concurrency and
            // elapsed discovery time, rather than silently ignoring later interests.
            using var searchBudget = CancellationTokenSource.CreateLinkedTokenSource(ct);
            searchBudget.CancelAfter(TimeSpan.FromSeconds(35));
            using var gate = new SemaphoreSlim(4);
            var jobs = Enumerable.Range(0, Math.Max(queries.Count, 8)).Select(async i =>
            {
                try
                {
                    await gate.WaitAsync(searchBudget.Token);
                    try
                    {
                        var fraction = (i + 1d) / (Math.Max(queries.Count, 8) + 1d);
                        return await SearchWithinAsync(queries[i % queries.Count],
                            SampleAlong(outbound.Geometry, fraction), 3000, searchBudget.Token);
                    }
                    finally { gate.Release(); }
                }
                catch (OperationCanceledException) when (!ct.IsCancellationRequested)
                {
                    return new DrivePlaceResults([], ["Some places could not be checked in time. Try planning again for more choices."]);
                }
            }).ToArray();
            var results = await Task.WhenAll(jobs);
            ct.ThrowIfCancellationRequested();
            warnings.AddRange(results.SelectMany(r => r.Warnings));
            var samples = Enumerable.Range(0, 65).Select(i => SampleAlong(outbound.Geometry, i / 64d)).ToArray();
            int Progress(DrivePlace p) => Enumerable.Range(0, samples.Length)
                .MinBy(i => RouteMath.DistanceMeters(samples[i], p.Location));
            var seen = new HashSet<string> { destination.PlaceId };
            var attempts = 0;
            // Round-robin results give each topic a chance before taking another
            // result from one topic. Stops remain ordered along the outbound route.
            foreach (var candidate in Enumerable.Range(0, 3).SelectMany(rank =>
                results.Where(r => r.Places.Count > rank).Select(r => r.Places[rank])))
            {
                if (accepted.Count >= request.MaxOptionalStops || attempts >= 16 ||
                    Total(route, accepted.Count) + request.MinutesPerStop > request.AvailableMinutes) break;
                if (!seen.Add(candidate.PlaceId) ||
                    RouteMath.DistanceMeters(request.Origin, candidate.Location) <= 300 ||
                    RouteMath.DistanceMeters(destination.Location, candidate.Location) <= 300 ||
                    accepted.Any(p => RouteMath.DistanceMeters(p.Location, candidate.Location) < 150)) continue;
                attempts++;
                var stops = accepted.Append(candidate).OrderBy(Progress).ToList();
                try
                {
                    var proposed = await routes.RouteAsync(request.Origin, Visits(stops), ct, preferences);
                    if (proposed.DrivingMinutes - route.DrivingMinutes <= preferences.MaxDetourMinutes &&
                        Total(proposed, stops.Count) <= request.AvailableMinutes)
                    {
                        accepted = stops;
                        route = proposed;
                    }
                }
                catch (DrivingUnavailableException)
                {
                    warnings.Add("An optional stop was skipped because its driving route was unavailable.");
                }
            }
        }
        var total = Total(route, accepted.Count);
        if (accepted.Count == 0) warnings.Add("No extra stops were added within your time and interests.");
        if (total > request.AvailableMinutes) warnings.Add("This trip exceeds your time budget. Increase the time or choose a closer destination.");
        return new(request.Origin, destination, request.ReturnToStart, accepted, route,
            (accepted.Count + 1) * request.MinutesPerStop, Buffer(route), total,
            request.AvailableMinutes, total <= request.AvailableMinutes, warnings.Distinct().ToArray()) { Preferences = preferences };
    }

    internal static GeoLocation SampleAlong(IReadOnlyList<GeoLocation> geometry, double fraction)
    {
        var lengths = geometry.Zip(geometry.Skip(1), RouteMath.DistanceMeters).ToArray();
        var target = lengths.Sum() * fraction;
        for (var i = 0; i < lengths.Length; i++)
        {
            if (target <= lengths[i] && lengths[i] > 0)
            {
                var t = target / lengths[i];
                return new(geometry[i].Latitude + (geometry[i + 1].Latitude - geometry[i].Latitude) * t,
                    geometry[i].Longitude + (geometry[i + 1].Longitude - geometry[i].Longitude) * t);
            }
            target -= lengths[i];
        }
        return geometry[^1];
    }
}
