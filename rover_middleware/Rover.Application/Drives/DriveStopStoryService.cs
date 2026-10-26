using Rover.Application.Journeys;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Drives;

public sealed record DriveStopStoryRequest(GeoLocation Location, string Query, string PlaceId);
public sealed record DriveStopStoryResult(string StoryTitle, string ShortSpokenNarration, string? PlaceId,
    IReadOnlyList<string> FactIdsUsed, IReadOnlyList<LocationSource> SourceReferences,
    double Confidence, IReadOnlyList<string> RequiredAttribution, IReadOnlyList<string> Warnings,
    string? ResearchStatus, DateTimeOffset ExpiresUtc);

public sealed class DriveStopStoryService(ScenicDriveService places, ILocalRouteResearcher researcher, TimeProvider clock)
{
    public async Task<DriveStopStoryResult> CreateAsync(DriveStopStoryRequest request, CancellationToken ct)
    {
        if (request is null || !ScenicDriveService.ValidLocation(request.Location) ||
            string.IsNullOrWhiteSpace(request.Query) || request.Query.Length > 256 ||
            string.IsNullOrWhiteSpace(request.PlaceId) || request.PlaceId.Length > 256)
            throw new ArgumentException("Select a valid driving stop.");
        var found = await places.SearchAsync(request.Query, request.Location, ct);
        var stop = found.Places.FirstOrDefault(p => p.PlaceId == request.PlaceId &&
            RouteMath.DistanceMeters(p.Location, request.Location) <= 500)
            ?? throw new ArgumentException("The selected stop could not be verified.");
        var now = clock.GetUtcNow();
        var place = new LocationPlace(stop.PlaceId, stop.Name, stop.Location, stop.Address,
            [], null, [], [], new Dictionary<string, string>(), 0, null, null, null,
            1, 1, [], [], null, null, now);
        var result = await NearbyStoryResearch.CreateAsync(researcher, place,
            new LocationStoryRequest(stop.Location, 300, null, null, [], [], [stop.PlaceId], "just-walking"),
            now, ct, selectedDriveStop: true);
        var expiry = result.SourceReferences.Where(s => s.ExpiresUtc.HasValue)
            .Select(s => s.ExpiresUtc!.Value).DefaultIfEmpty(now.AddHours(12)).Min();
        // Trip-local preparation is deliberately short-lived, not a reusable content archive.
        return new(result.StoryTitle, result.ShortSpokenNarration, result.PlaceId, result.FactIdsUsed,
            result.SourceReferences, result.Confidence, result.RequiredAttribution, result.Warnings,
            result.ResearchStatus, expiry < now.AddHours(12) ? expiry : now.AddHours(12));
    }
}

