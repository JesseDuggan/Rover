using Rover.Application.Journeys;
using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;

internal static class NearbyStoryResearchTests
{
    public static async Task Validation()
    {
        var now = DateTimeOffset.UtcNow;
        var point = new GeoLocation(50, 8);
        var place = new LocationPlace("cafe", "Coffee Club", point, "Test street",
            [], null, [], [], new Dictionary<string, string>(), 0, null, null,
            null, 1, 1, [], [], null, null, now);
        var request = new LocationStoryRequest(point, 500, null, null, [], ["history"], ["cafe"], "just-walking");
        var story = new AdaptiveRouteStory("story", "nearby", "research-id", "Coffee Club history",
            RouteStoryIntent.HiddenHistory, "history", point, 0, 0,
            [new(AdaptiveStoryLength.Standard, 60, "Coffee Club has documented history.", ["claim"])],
            [new("claim", "Coffee Club has documented history.", ["source"], .9)],
            [new("source", "Archive", "History", "https://example.org/history", "Archive", now, .9)],
            .9, now.AddDays(1));
        var researcher = new FakeResearcher(new([story], null));
        var result = await NearbyStoryResearch.CreateAsync(researcher, place, request, now, default);
        Check(result.ResearchStatus == "ready" && result.PlaceId == "cafe"
            && result.FactIdsUsed.Single() == "claim" && result.SourceReferences.Single().SourceUrl == "https://example.org/history",
            "Valid cited story must preserve identity and evidence.");
        Check(researcher.Query?.MaximumStories == 1
            && researcher.Query.PublicPlaces?.Single().Location == point, "Research must be bounded to selected place.");
        foreach (var invalid in new[] {
            story with { Anchor = new GeoLocation(51, 8) },
            story with { Claims = [new("claim", "Another business has history.", ["source"], .9)] },
            story with { Sources = [] },
            story with { ExpiresUtc = now.AddMinutes(-1) }
        })
        {
            result = await NearbyStoryResearch.CreateAsync(new FakeResearcher(new([invalid], null)), place, request, now, default);
            Check(result.ResearchStatus == "empty" && result.ShortSpokenNarration == "", "Unsafe evidence must not play.");
        }
        result = await NearbyStoryResearch.CreateAsync(new FakeResearcher(new([], "failure") { Failed = true }), place, request, now, default);
        Check(result.ResearchStatus == "failed", "Failure must not look like no evidence.");
        result = await NearbyStoryResearch.CreateAsync(researcher, place, request with { SelectedPlaceIds = ["other"] }, now, default);
        Check(result.ResearchStatus == "empty", "Must not substitute another place.");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try {
            await NearbyStoryResearch.CreateAsync(researcher, place, request, now, cancelled.Token);
            throw new Exception("Cancellation must propagate.");
        } catch (OperationCanceledException) { }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }

    private sealed class FakeResearcher(LocalRouteResearchResult result) : ILocalRouteResearcher
    {
        public LocalRouteResearchQuery? Query { get; private set; }
        public Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken cancellationToken)
        {
            Query = query;
            return Task.FromResult(result);
        }
    }
}
