using Rover.Application.Journeys;
using Rover.Application.LiveContext;
using Rover.Application.Walks;

namespace Rover.Application.LocationIntelligence;

public static class NearbyStoryResearch
{
    public static async Task<LocationStoryResult> CreateAsync(
        ILocalRouteResearcher? researcher, LocationPlace? place,
        LocationStoryRequest request, DateTimeOffset now, CancellationToken cancellationToken)
    {
        LocationStoryResult Empty(string status) => new(
            place?.Name ?? "Nearby story", "", null, place?.CanonicalId,
            [], [], 0, [], []) { ResearchStatus = status };

        if (place is null || request.SelectedPlaceIds.Count != 1
            || !request.SelectedPlaceIds.Contains(place.CanonicalId)
            || RouteMath.DistanceMeters(request.UserCoordinates, place.Coordinates) > 500)
            return Empty("empty");
        if (researcher is null) return Empty("failed");

        // A point-sized research area, not a fabricated walking route.
        var segment = new RouteStorySegment(
            "nearby", 0, place.Coordinates, place.Coordinates, place.Coordinates,
            0, 0, 0, 0, false, []);
        var query = new LocalRouteResearchQuery(
            [segment], new ApproximateLiveLocation(place.City, place.Region, place.CountryCode, null),
            [place.Name], request.Interests.ToArray(), "en",
            [new LocalResearchPublicPlace(place.Name, place.Address, place.Coordinates)])
        { MaximumStories = 1 };

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(35));
        LocalRouteResearchResult result;
        try
        {
            result = await researcher.ResearchAsync(query, timeout.Token).WaitAsync(timeout.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return Empty("failed");
        }
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            return Empty("failed");
        }
        cancellationToken.ThrowIfCancellationRequested();
        foreach (var story in result.Stories)
        {
            var variant = story.Variants.FirstOrDefault(v => v.Length == AdaptiveStoryLength.Standard)
                ?? story.Variants.OrderByDescending(v => v.EstimatedDurationSeconds).FirstOrDefault();
            if (variant is null || string.IsNullOrWhiteSpace(variant.Narration)
                || variant.ClaimIds.Count == 0 || story.ExpiresUtc <= now
                || !double.IsFinite(story.Anchor.Latitude) || !double.IsFinite(story.Anchor.Longitude)
                || RouteMath.DistanceMeters(place.Coordinates, story.Anchor) > 150
                || !string.Join(" ", story.Claims.Select(c => c.Text)).Contains(place.Name, StringComparison.OrdinalIgnoreCase))
                continue;
            var claims = story.Claims.Where(c => variant.ClaimIds.Contains(c.ClaimId)).ToArray();
            var sources = story.Sources.Where(s => claims.Any(c => c.SourceIds.Contains(s.SourceId))
                && Uri.TryCreate(s.Url, UriKind.Absolute, out var uri)
                && (uri.Scheme == "https" || uri.Scheme == "http")).ToArray();
            if (claims.Length != variant.ClaimIds.Distinct().Count()
                || claims.Any(c => c.SourceIds.Count == 0
                    || c.SourceIds.Any(id => !sources.Any(s => s.SourceId == id))))
                continue;
            // Research does not confer permission to persist third-party content.
            return new LocationStoryResult(
                story.Title, variant.Narration, null, place.CanonicalId,
                claims.Select(c => c.ClaimId).ToArray(),
                sources.Select(s => new LocationSource(s.ProviderName, s.SourceId, s.Url,
                    s.Attribution, s.Reuse?.LicenseId, s.RetrievedUtc, s.Confidence)
                    { SourceTitle = s.Title, ExpiresUtc = story.ExpiresUtc }).ToArray(),
                story.EvidenceScore, sources.Select(s => s.Attribution).Distinct().ToArray(), [])
                { ResearchStatus = "ready" };
        }
        return Empty(result.Failed ? "failed" : "empty");
    }
}
