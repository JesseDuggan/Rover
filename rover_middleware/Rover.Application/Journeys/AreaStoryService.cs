using Microsoft.Extensions.Logging;
using Rover.Application.LiveContext;
using Rover.Application.Drives;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Journeys;

public sealed record AreaStoryRequest(double Latitude, double Longitude,
    IReadOnlyList<string>? Interests, IReadOnlyList<string>? ExcludedTitles, int SearchRadiusMeters = 1000, string? ContentDepth = null,
    bool NeighbourhoodContext = false);
public sealed record AreaStoryCollection(string Status, IReadOnlyList<AdaptiveRouteStory> Stories, int SearchRadiusMeters = 1000);

public sealed class AreaStoryService(ILocalRouteResearcher researcher, TimeProvider clock,
    ILogger<AreaStoryService> logger, ScenicDriveService? places = null)
{
    public async Task<AreaStoryCollection> ResearchAsync(AreaStoryRequest request, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (request.SearchRadiusMeters is not (1000 or 5000 or 20000))
            throw new ArgumentException("Search radius must be 1000, 5000 or 20000 metres.");
        if (!double.IsFinite(request.Latitude) || !double.IsFinite(request.Longitude)
            || Math.Abs(request.Latitude) > 90 || Math.Abs(request.Longitude) > 180)
            throw new ArgumentException("A valid current location is required.");
        if (request.Interests?.Count > 16 || request.ExcludedTitles?.Count > 120
            || (request.Interests ?? []).Any(x => string.IsNullOrWhiteSpace(x) || x.Length > 120)
            || (request.ExcludedTitles ?? []).Any(x => string.IsNullOrWhiteSpace(x) || x.Length > 160))
            throw new ArgumentException("Story interests or exclusions exceed the allowed size.");
        var center = new GeoLocation(request.Latitude, request.Longitude);
        StoryInspection.Record("Neighbourhood preparation", "Started",
            $"Area research; interests: {string.Join(", ", request.Interests ?? [])}; radius {request.SearchRadiusMeters} m; excluding {request.ExcludedTitles?.Count ?? 0} already covered titles.",
            depth: StoryPreparationPolicy.Depth(request.ContentDepth));
        // Adapter to the citation researcher: this is a search anchor, not a saved route.
        var anchor = new RouteStorySegment("area", 0, center, center, center, 0, 0, 0, 0, false, []);
        List<LocalResearchPublicPlace> leads = [];
        if (!request.NeighbourhoodContext && request is { SearchRadiusMeters: 1000, ExcludedTitles.Count: > 0 } && places is not null)
        {
            leads.AddRange(await places.NearbyStoryPlacesAsync(center, 1000, request.Interests ?? [], cancellationToken));
        }
        var query = new LocalRouteResearchQuery([anchor], new ApproximateLiveLocation(null, null, null, null),
            leads.Select(p => p.Name).ToArray(), (request.Interests ?? []).Distinct(StringComparer.OrdinalIgnoreCase).ToArray(), "en", leads)
        {
            ContentDepth = StoryPreparationPolicy.Depth(request.ContentDepth),
            AreaFirst = true, MaximumStories = 3,
            IncludeNeighbourhoodStories = request.NeighbourhoodContext,
            SearchRadiusMeters = request.SearchRadiusMeters,
            ExcludedStoryTitles = request.ExcludedTitles ?? []
        };
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        budget.CancelAfter(TimeSpan.FromSeconds(95));
        LocalRouteResearchResult result;
        try {
            result = await researcher.ResearchAsync(query, budget.Token).WaitAsync(budget.Token);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception exception) {
            logger.LogWarning("Area research failed: {Kind}", exception.GetType().Name);
            StoryInspection.Record("Neighbourhood preparation", "Failed", "Research did not finish: " + exception.GetType().Name);
            return new("failed", [], request.SearchRadiusMeters);
        }
        cancellationToken.ThrowIfCancellationRequested();
        var now = clock.GetUtcNow();
        var excluded = new HashSet<string>((request.ExcludedTitles ?? []).Select(x => x.Trim()), StringComparer.OrdinalIgnoreCase);
        var stories = result.Stories.Where(s => !excluded.Contains(s.Title.Trim())
            && s.ExpiresUtc > now && s.Claims.Count > 0 && s.Sources.Count > 0
            && s.Variants.Any(v => !string.IsNullOrWhiteSpace(v.Narration))
            && double.IsFinite(s.Anchor.Latitude) && double.IsFinite(s.Anchor.Longitude)
            && (s.ContextOrigin is { } origin && s.GeographicScope != "local"
                ? RouteMath.DistanceMeters(center, origin) <= 1000
                : RouteMath.DistanceMeters(center, s.Anchor) <= request.SearchRadiusMeters)
            && s.Claims.All(c => c.SourceIds.Count > 0 && c.SourceIds.All(id =>
                s.Sources.Any(source => source.SourceId == id && Uri.TryCreate(source.Url, UriKind.Absolute, out var uri)
                    && uri.Scheme is "http" or "https"))))
            .DistinctBy(s => s.Title.Trim().ToLowerInvariant()).Take(3).ToArray();
        var status = stories.Length > 0 ? "ready" : result.Failed ? "failed" : "empty";
        foreach (var story in stories) StoryInspection.Story(story, "Neighbourhood story");
        foreach (var rejected in result.Stories.Except(stories))
            StoryInspection.Record("Neighbourhood story", "Not retained",
                excluded.Contains(rejected.Title.Trim()) ? "Already covered title." :
                "Did not pass freshness, location, narration or claim/source checks, or exceeded the three-story limit.", rejected.StoryId, rejected.Title);
        StoryInspection.Record("Neighbourhood preparation", status,
            $"Retained {stories.Length} of {result.Stories.Count} researched area chapters. POI narration is prepared separately; an empty result does not establish absence of local history.",
            depth: StoryPreparationPolicy.Depth(request.ContentDepth));
        logger.LogInformation("Area story research: {Status}; stories={Count}; radiusMeters={Radius}", status, stories.Length, request.SearchRadiusMeters);
        return new(status, stories, request.SearchRadiusMeters);
    }
}
