using Rover.Application.Journeys;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Drives;

public sealed record DriveStopStoryRequest(GeoLocation Location, string Query, string PlaceId, string[]? Interests = null, GeoLocation? JourneyStart = null, GeoLocation? JourneyEnd = null, string? ContentDepth = null);
public sealed record DriveStopStoryResult(string StoryTitle, string ShortSpokenNarration, string? PlaceId,
    IReadOnlyList<string> FactIdsUsed, IReadOnlyList<LocationSource> SourceReferences,
    double Confidence, IReadOnlyList<string> RequiredAttribution, IReadOnlyList<string> Warnings,
    string? ResearchStatus, DateTimeOffset ExpiresUtc);

public sealed class DriveStopStoryService(ScenicDriveService places, ILocalRouteResearcher researcher, TimeProvider clock, IEnumerable<ILocationContextProvider>? contextProviders = null)
{
    public async Task<DriveStopStoryResult> CreateAsync(DriveStopStoryRequest request, CancellationToken ct)
    {
        if (request is null || !ScenicDriveService.ValidLocation(request.Location) ||
            string.IsNullOrWhiteSpace(request.Query) || request.Query.Length > 256 ||
            request.PlaceId is null || request.PlaceId.Length > 256 ||
            request.Interests is { Length: > 20 } || request.Interests?.Any(i => string.IsNullOrWhiteSpace(i) || i.Length > 80) == true ||
            request.JourneyStart is not null && !ScenicDriveService.ValidLocation(request.JourneyStart) ||
            request.JourneyEnd is not null && !ScenicDriveService.ValidLocation(request.JourneyEnd))
            throw new ArgumentException("Select a valid driving stop.");
        LocationPlace? place = null;
        if (!string.IsNullOrWhiteSpace(request.PlaceId))
            foreach (var provider in (contextProviders ?? []).OfType<ISelectedLocationProvider>())
                if ((place = await provider.FindSelectedAsync(request.PlaceId, ct)) is not null) break;
        var now = clock.GetUtcNow();
        if (place is null)
        {
            var found = await places.SearchAsync(request.Query, request.Location, ct);
            var matches = found.Places.Where(p => string.IsNullOrWhiteSpace(request.PlaceId)
                ? string.Equals(p.Name, request.Query.Trim(), StringComparison.OrdinalIgnoreCase)
                    && RouteMath.DistanceMeters(p.Location, request.Location) <= 150
                : p.PlaceId == request.PlaceId && RouteMath.DistanceMeters(p.Location, request.Location) <= 500).ToArray();
            var stop = matches.Length == 1 ? matches[0]
                : throw new ArgumentException("The selected stop could not be uniquely verified.");
            place = new LocationPlace(stop.PlaceId, stop.Name, stop.Location, stop.Address,
                stop.Categories, null, [], [], new Dictionary<string, string>(), 0, null, null, null,
                1, 1, [], [], null, null, now);
        }
        if (RouteMath.DistanceMeters(place.Coordinates, request.Location) > 500)
            throw new ArgumentException("The selected stop is outside the requested location.");
        var result = await NearbyStoryResearch.CreateAsync(researcher, place,
            new LocationStoryRequest(place.Coordinates, 300, null, null, new[] { request.JourneyStart, request.JourneyEnd }.OfType<GeoLocation>().ToArray(), request.Interests ?? [], [place.CanonicalId], "just-walking") { ContentDepth = request.ContentDepth },
            now, ct, selectedDriveStop: true);
        var expiry = result.SourceReferences.Where(s => s.ExpiresUtc.HasValue)
            .Select(s => s.ExpiresUtc!.Value).DefaultIfEmpty(now.AddHours(12)).Min();
        // Trip-local preparation is deliberately short-lived, not a reusable content archive.
        return new(result.StoryTitle, result.ShortSpokenNarration, result.PlaceId, result.FactIdsUsed,
            result.SourceReferences, result.Confidence, result.RequiredAttribution, result.Warnings,
            result.ResearchStatus, expiry < now.AddHours(12) ? expiry : now.AddHours(12));
    }
}

