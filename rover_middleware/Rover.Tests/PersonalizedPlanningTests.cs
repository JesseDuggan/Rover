using Rover.Application.Walks;
using Rover.Domain.Walks;
using Rover.Infrastructure.Walks;

internal static class PersonalizedPlanningTests
{
    private static readonly CreateWalkCommand Command = new(new(43.65, -79.48), 90,
        ["history", "nature"], WalkingPace.Leisurely, []);
    private static WalkStop Stop(string id, string category, double offset) => new(id, 1, id,
        new(43.65 + offset, -79.48), category, "Existing narration", category,
        ContentType.History, ContentSource.LocalRecommendation, 2, 0, 40,
        discoveryProviderName: "GooglePlaces", providerPlaceId: id);
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }

    public static Task InterestSpacingAndAlternatives()
    {
        Check(Command.WalkingSecondsAtPace(100) == 135, "Easy pace must apply to regular walks as well as Journey Lab.");
        Check(Command.WalkingSecondsAtPace(100) == (Command with { LimitLabDetours = true }).WalkingSecondsAtPace(100), "Regular and lab walks must use the same pace estimate.");
        var museum = Stop("near-museum", "Museum", .001);
        var park = Stop("near-park", "Park", .003);
        var remote = Stop("remote-museum", "Museum", .025);
        var shop = Stop("shop", "Store", .0008);
        var pool = new[] { museum, park, remote, shop };
        var chosen = PersonalizedStopPlan.Select(Command, pool, [remote], 2);
        Check(chosen.Contains(museum) && chosen.Contains(park), "Nearby requested interests should beat a distant model-selected stop and an unmatched shop.");
        var shopping = PersonalizedStopPlan.Select(Command with { Interests = ["shopping"] }, pool, [], 1);
        Check(shopping[0] == shop, "Changing interests must change selection.");
        var alternative = Stop("another-museum", "Museum", .0025);
        var next = PersonalizedStopPlan.Select(Command with { PreviousStopIds = [museum.StopId] }, [museum, alternative], [], 1);
        Check(next[0] == alternative, "Try another should prefer comparable unshown places.");
        var limited = PersonalizedStopPlan.Select(Command with { PreviousStopIds = [museum.StopId, park.StopId] }, [museum, park], [], 2);
        Check(limited.Length == 2, "Limited nearby choice must allow repeats, not fail.");
        Check(WalkInterestPolicy.MatchedInterests(museum, ["history", "hidden gems", "weather"]).SequenceEqual(["history"]), "Story lenses must not invent place evidence.");
        Check(!WalkInterestPolicy.Allows(Stop("restaurant", "Restaurant", .001), ["history", "coffee"]), "Coffee alone must not authorize restaurant stops.");
        Check(WalkInterestPolicy.IsFood("café"), "Accented cafe category must remain supported.");
        return Task.CompletedTask;
    }
}
