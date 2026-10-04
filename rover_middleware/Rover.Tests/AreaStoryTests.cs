using Microsoft.Extensions.Logging.Abstractions;
using Rover.Application.Journeys;
using Rover.Domain.Walks;

internal static class AreaStoryTests
{
    public static async Task RouteFreeResearch()
    {
        var center = new GeoLocation(52.373, 4.883);
        var now = DateTimeOffset.UtcNow;
        var source = new AdaptiveStorySource("archive", "Archive", "Area history",
            "https://example.org/history", "Archive", now, .9);
        var story = new AdaptiveRouteStory("area-1", "area", "", "Neighbourhood history",
            RouteStoryIntent.NeighbourhoodHistory, "history", center, 0, 0,
            [new(AdaptiveStoryLength.Standard, 60, "The neighbourhood has documented history.", ["claim"])],
            [new("claim", "The neighbourhood has documented history.", ["archive"], .9)],
            [source], .9, now.AddHours(6));
        var fake = new Researcher(new([story], null));
        var service = new AreaStoryService(fake, TimeProvider.System, NullLogger<AreaStoryService>.Instance);
        var request = new AreaStoryRequest(center.Latitude, center.Longitude, ["history"], []);
        var result = await service.ResearchAsync(request, default);
        Check(result.Status == "ready" && result.Stories.Count == 1, "Fresh city must produce area stories.");
        Check(fake.Query is { AreaFirst: true, MaximumStories: 3 }
            && fake.Query.PublicPlaceNames.Count == 0 && fake.Query.Journey is null
            && fake.Query.Interests.Contains("local events"), "No old route or POI may be required.");
        result = await service.ResearchAsync(request with { ExcludedTitles = ["Neighbourhood history"] }, default);
        Check(result.Stories.Count == 0 && fake.Query!.ExcludedStoryTitles.Count == 1, "Exclude previously collected titles.");
        foreach (var invalid in new[] { story with { Sources = [] },
            story with { ExpiresUtc = now.AddHours(-1) },
            story with { Anchor = new GeoLocation(48, 8) } }) {
            fake.Result = new([invalid], null);
            result = await service.ResearchAsync(request, default);
            Check(result.Status == "empty", "Reject unsourced, expired or distant stories.");
        }
        fake.Result = new([], "Provider failed") { Failed = true };
        Check((await service.ResearchAsync(request, default)).Status == "failed", "Expose failure separately.");
        var regional = story with { Anchor = new GeoLocation(52.4, 4.883) };
        fake.Result = new([regional], null);
        Check((await service.ResearchAsync(request, default)).Stories.Count == 0, "Local search rejects regional anchor.");
        var broader = await service.ResearchAsync(request with { SearchRadiusMeters = 5000 }, default);
        Check(broader.Stories.Count == 1 && broader.SearchRadiusMeters == 5000
            && fake.Query!.SearchRadiusMeters == 5000, "Regional scope must be explicit and passed to researcher.");
        Check(broader.Stories[0].Anchor == regional.Anchor, "Do not relocate regional subjects to the walker.");
        try {
            await service.ResearchAsync(request with { SearchRadiusMeters = 50000 }, default);
            throw new Exception("Unbounded search accepted.");
        } catch (ArgumentException) { }
        try {
            await service.ResearchAsync(request with { Latitude = double.NaN }, default);
            throw new Exception("Invalid coordinates accepted.");
        } catch (ArgumentException) { }
    }
    private static void Check(bool condition, string message) {
        if (!condition) throw new Exception(message);
    }
    private sealed class Researcher(LocalRouteResearchResult result) : ILocalRouteResearcher {
        public LocalRouteResearchQuery? Query;
        public LocalRouteResearchResult Result = result;
        public Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken token) {
            Query = query;
            return Task.FromResult(Result);
        }
    }
}
