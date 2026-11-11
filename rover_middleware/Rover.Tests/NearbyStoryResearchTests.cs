using Rover.Application.Journeys;
using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;

internal static class NearbyStoryResearchTests
{
    public static async Task SharedPreparation()
    {
        // Synthetic evidence isolates orchestration; this is not a historical claim.
        var now = DateTimeOffset.UtcNow;
        var point = new GeoLocation(44.9008, -76.2493);
        var place = new LocationPlace("perth-test", "Perth test site", point, "Perth, Ontario",
            ["museum"], null, [], [], new Dictionary<string, string>(), 0, null, null,
            null, 1, 1, [], [], null, null, now);
        var story = new AdaptiveRouteStory("perth-story", "nearby", place.CanonicalId, "Test evidence",
            RouteStoryIntent.HiddenHistory, "history", point, 0, 0,
            [new(AdaptiveStoryLength.Standard, 30, "Perth test site short fixture.", ["claim"]),
             new(AdaptiveStoryLength.Deep, 90, "Perth test site deeper fixture with additional context.", ["claim"])],
            [new("claim", "Perth test site fixture evidence.", ["source"], .9)],
            [new("source", "Test archive", "Fixture", "https://example.org/fixture", "Test", now, .9)],
            .9, now.AddHours(1)) { AudienceSuitability = "family" };
        var request = new LocationStoryRequest(point, 300, null, null, [], ["history", "architecture"],
            [place.CanonicalId], "just-walking") { ContentDepth = "Deeper stories" };
        var regular = new FakeResearcher(new([story], null));
        var lab = new FakeResearcher(new([story], null));
        var a = await NearbyStoryResearch.CreateAsync(regular, place, request, now, default);
        var b = await NearbyStoryResearch.CreateAsync(lab, place, request, now, default, selectedDriveStop: true);
        Check(a.ShortSpokenNarration == b.ShortSpokenNarration && a.ShortSpokenNarration.Contains("deeper"),
            "Regular and prepared/Lab paths select the same requested depth.");
        Check(regular.Query!.ContentDepth == "deep" && lab.Query!.ContentDepth == "deep"
            && regular.Query.Interests.SequenceEqual(request.Interests)
            && regular.Query.Question == lab.Query.Question,
            "Both paths send the same place research question, interests and normalized depth.");
        var brief = await NearbyStoryResearch.CreateAsync(regular, place, request with { ContentDepth = "standard" }, now, default);
        Check(brief.ShortSpokenNarration.Contains("short fixture"), "Standard preparation selects standard narration.");
        var calls = 0;
        var recovery = new CapturingRouteResearcher(_ => ++calls == 1
            ? new([story with { Variants = [new(AdaptiveStoryLength.Deep, 40, "Perth test site is rich in history.", ["claim"])] }], null)
            : new([story], null));
        var richer = await NearbyStoryResearch.CreateAsync(recovery, place, request, now, default);
        Check(calls == 2 && richer.ShortSpokenNarration.Contains("deeper fixture"),
            "Generic narration receives one bounded targeted recovery pass.");
    }

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
            .9, now.AddDays(1)) { AudienceSuitability = "family" };
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
            story with { Variants = [new(AdaptiveStoryLength.Standard, 30, "I could not verify a place called Coffee Club here.", ["claim"])] },
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
