using Rover.Application.Journeys;
using Rover.Application.LiveContext;
using Rover.Application.Walks;

namespace Rover.Application.LocationIntelligence;

public static class NearbyStoryResearch
{
    public static async Task<LocationStoryResult> CreateAsync(
        ILocalRouteResearcher? researcher, LocationPlace? place,
        LocationStoryRequest request, DateTimeOffset now, CancellationToken cancellationToken,
        bool selectedDriveStop = false)
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
        {
            MaximumStories = 1,
            Question = selectedDriveStop ? new StoryResearchQuestion(
                $"What documented event or human story took place at {place.Name} at {place.Address}, and why is it remembered? " +
                (request.RouteGeometry.Count == 2 ? FormattableString.Invariant($"This walking journey starts at {request.RouteGeometry[0].Latitude:F4},{request.RouteGeometry[0].Longitude:F4} and ends at {request.RouteGeometry[1].Latitude:F4},{request.RouteGeometry[1].Longitude:F4}. ") : "") +
                "For a cinema or festival venue, which named film actually screened in THIS building? For a theatre or concert hall, which named production played on THIS stage? For another kind of place, find a documented local happening, person or turning point. Search local-language venue programmes and archives using former venue names as needed. In the first sentence name the place and the specific work or episode together. Cite the evidence tying them together; describe its date and significance in a single short family-friendly paragraph. Only call a screening a premiere if the source specifies that distinction. If the evidence cannot establish a specific connection, return no story. " +
                "Do not substitute nearby attractions or invent access, parking, opening hours or safety advice.",
                StoryQuestionScope.Street, StoryQuestionFormat.Single, 1, 90) : null
        };

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(selectedDriveStop ? 90 : 35));
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
            if (selectedDriveStop && !story.CanAutoplay) continue;
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
