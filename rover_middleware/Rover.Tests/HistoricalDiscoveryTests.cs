using System.Net;
using System.Text.Json;
using Rover.Application.Journeys;
using Rover.Application.LiveContext;
using Rover.Domain.Walks;
using Rover.Infrastructure.Journeys;

internal static class HistoricalDiscoveryTests
{
    public static async Task Discovery()
    {
        using var handler = new Handler();
        using var discovery = new HistoricalSubjectDiscovery(new Factory(handler));
        var anchor = new GeoLocation(52.1, 4.3);
        var segment = new RouteStorySegment("area", 0, anchor, anchor, anchor, 0, 0, 0, 0, false, []);
        var query = new LocalRouteResearchQuery([segment], new ApproximateLiveLocation(null, null, null, null), [], ["history"], "en") { AreaFirst = true };
        var subjects = await discovery.FindAsync(query, default);
        Check(subjects.Count == 1 && subjects[0].EntityUrl == "https://www.wikidata.org/wiki/Q123",
            "Only valid nearby coordinates and canonical entity URLs survive.");
        Check(subjects[0].Location == anchor && handler.Query!.Contains("wd:Q178561") && !handler.Query.Contains("wd:Q41176"),
            "History discovers battle sites without requesting all buildings.");
        await discovery.FindAsync(query, default);
        Check(handler.Calls == 1, "Share cached discovery between visitors.");
        await discovery.FindAsync(query with { Interests = ["food"] }, default);
        Check(handler.Calls == 1, "Food-only interests must not trigger history discovery.");
        await discovery.FindAsync(query with { Interests = ["architecture"] }, default);
        Check(handler.Calls == 2 && handler.Query!.Contains("wd:Q41176") && !handler.Query.Contains("wd:Q178561"), "Interest-specific cache and lookup.");
        var other = new GeoLocation(48.85, 2.35);
        await discovery.FindAsync(query with { Segments = [segment with { Anchor = other, Start = other, End = other }] }, default);
        Check(handler.Query!.Contains("Point(2.35 48.85)"), "A new city uses current coordinates without a saved route.");
        handler.Fail = true;
        Check((await discovery.FindAsync(query with { Interests = ["culture"] }, default)).Count == 0, "Discovery failure is optional, not a research failure.");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try { await discovery.FindAsync(query, cancelled.Token); throw new Exception("Cancellation swallowed"); }
        catch (OperationCanceledException) { }
        Check(!StoryInterestPolicy.Allows("history", ["food"]) && StoryInterestPolicy.Allows("people", ["notable people"])
            && StoryInterestPolicy.Allows("pop_culture", ["film and television"]) && StoryInterestPolicy.Allows("history", []), "Preference aliases and empty-profile defaults.");
    }
    private static void Check(bool valid, string message) { if (!valid) throw new Exception(message); }
    private sealed class Factory(HttpMessageHandler handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(handler, false);
    }
    private sealed class Handler : HttpMessageHandler
    {
        public int Calls;
        public string? Query;
        public bool Fail;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Query = Uri.UnescapeDataString(request.RequestUri!.Query);
            if (Fail) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.TooManyRequests));
            object Row(string id, string point) => new { place = new { value = id }, placeLabel = new { value = "Test statue" }, location = new { value = point } };
            var json = JsonSerializer.Serialize(new { results = new { bindings = new[] {
                Row("http://www.wikidata.org/entity/Q123", "Point(4.3 52.1)"),
                Row("https://evil.example/Q123", "Point(4.3 52.1)"),
                Row("http://www.wikidata.org/entity/Q124", "Point(4.3 95)"),
                Row("http://www.wikidata.org/entity/Q125", "Point(10 40)"),
                Row("http://www.wikidata.org/entity/Q126", "Point(NaN 52.1)") } } });
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json) });
        }
    }
}
