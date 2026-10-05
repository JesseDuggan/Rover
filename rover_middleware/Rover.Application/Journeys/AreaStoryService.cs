using Microsoft.Extensions.Logging;
using Rover.Application.LiveContext;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Journeys;

public sealed record AreaStoryRequest(double Latitude, double Longitude,
    IReadOnlyList<string>? Interests, IReadOnlyList<string>? ExcludedTitles, int SearchRadiusMeters = 1000);
public sealed record AreaStoryCollection(string Status, IReadOnlyList<AdaptiveRouteStory> Stories, int SearchRadiusMeters = 1000);

public sealed class AreaStoryService(ILocalRouteResearcher researcher, TimeProvider clock,
    ILogger<AreaStoryService> logger)
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
        // Adapter to the citation researcher: this is a search anchor, not a saved route.
        var anchor = new RouteStorySegment("area", 0, center, center, center, 0, 0, 0, 0, false, []);
        var query = new LocalRouteResearchQuery([anchor], new ApproximateLiveLocation(null, null, null, null),
            [], (request.Interests ?? []).Prepend("local events").Distinct().ToArray(), "en")
        {
            AreaFirst = true, MaximumStories = 3,
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
        logger.LogInformation("Area story research: {Status}; stories={Count}; radiusMeters={Radius}", status, stories.Length, request.SearchRadiusMeters);
        return new(status, stories, request.SearchRadiusMeters);
    }
}
