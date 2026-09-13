using System.Net;
using System.Text;
using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;
using Rover.Infrastructure.Walks;

internal static class StoryLedPlanningTests
{
    private static readonly CreateWalkCommand Command = new(new(43.65, -79.4), 60, ["history"], WalkingPace.Standard, []);
    private static WalkStop Stop(string id, int index) => new(id, index, $"Museum {index}",
        new(43.65 + index * 0.001, -79.4), "Local museum", "Existing narration.", "Museum",
        ContentType.History, ContentSource.LocalRecommendation, 5, 100, 40,
        discoveryProviderName: "GooglePlaces", providerPlaceId: id, sourceUrl: $"https://maps.google.com/?cid={id}",
        requiredAttribution: ["Google Maps"]);
    private static WalkStop[] Pool => [Stop("a", 1), Stop("b", 2), Stop("c", 3)];
    private static OpenAIStoryLedStopSelector Selector(Handler handler, bool enabled = true, string? key = "test")
        => new(new HttpClient(handler), new() { Enabled = enabled, ApiKey = key, Model = "test-model", TimeoutSeconds = 1 }, [], TimeProvider.System);
    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
    }

    public static async Task SelectionValidation()
    {
        var pool = Pool;
        var handler = new Handler { Ids = ["c", "a"] };
        var selected = await Selector(handler).SelectAsync(Command, pool, 3, default);
        Check(selected.Stops.Count == 2 && ReferenceEquals(selected.Stops[0], pool[2]), "Must retain sourced objects and priority.");
        using var request = JsonDocument.Parse(handler.Request!);
        Check(request.RootElement.GetProperty("store").GetBoolean() == false, "Disable response storage.");
        Check(request.RootElement.GetProperty("text").GetProperty("format").GetProperty("strict").GetBoolean(), "Strict schema required.");
        Check(!handler.Request!.Contains("latitude", StringComparison.OrdinalIgnoreCase), "Do not send precise GPS.");
        foreach (var ids in new[] { new[] { "a", "invented" }, new[] { "a", "a" }, new[] { "a" }, new[] { "a", "b", "c", "d" } })
        {
            var bad = await Selector(new Handler { Ids = ids }).SelectAsync(Command, pool, 3, default);
            Check(bad.Stops.Count == 0, "Invalid selection must fall back wholesale.");
        }
        var incomplete = await Selector(new Handler { Status = "incomplete" }).SelectAsync(Command, pool, 3, default);
        Check(incomplete.Stops.Count == 0, "Incomplete output must not be accepted.");
        var duplicate = await Selector(new Handler()).SelectAsync(Command, [pool[0], pool[0]], 3, default);
        Check(duplicate.Stops.Count == 0, "Duplicate provider IDs must not enter selection.");
    }

    public static async Task FailureAndCancellation()
    {
        foreach (var selector in new[] { Selector(new Handler(), false), Selector(new Handler(), true, null),
            Selector(new Handler { Code = HttpStatusCode.TooManyRequests }), Selector(new Handler { Malformed = true }),
            Selector(new Handler { Delay = true }) })
        {
            var result = await selector.SelectAsync(Command, Pool, 3, default);
            Check(result.Stops.Count == 0, "Unavailable planner must fall back.");
        }
        using var cancellation = new CancellationTokenSource();
        cancellation.CancelAfter(50);
        try
        {
            await Selector(new Handler { Delay = true }).SelectAsync(Command, Pool, 3, cancellation.Token);
            throw new InvalidOperationException("Parent cancellation was swallowed.");
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
    }

    public static async Task EvidenceMatching()
    {
        var stop = Pool[0];
        var now = DateTimeOffset.UtcNow;
        var source = new LocationSource("Wikipedia", "1", "https://en.wikipedia.org/wiki/Museum", "Wikipedia contributors",
            "CC BY-SA", now, 0.86) { ExpiresUtc = now.AddHours(1) };
        var fact = new LocationFact("f", "encyclopedic_summary", "A sourced historical passage.", source, 0.86, true, now);
        var article = new LocationPlace("wiki:1", stop.Name, stop.Location, null, [], null, [fact], [source],
            new Dictionary<string, string>(), null, null, null, null, 0.86, 1, [], [], null, null, now);
        Check(OpenAIStoryLedStopSelector.MatchedEvidence(stop, [article], now).Length == 1, "Matching evidence retained.");
        Check(OpenAIStoryLedStopSelector.MatchedEvidence(stop, [article with { Name = "Different museum" }], now).Length == 0, "Nearby does not establish identity.");
        Check(OpenAIStoryLedStopSelector.MatchedEvidence(stop, [article with { Coordinates = new(44, -79.4) }], now).Length == 0, "Namesake at distance rejected.");
        Check(OpenAIStoryLedStopSelector.MatchedEvidence(stop, [article], now.AddHours(2)).Length == 0, "Expired evidence rejected.");
        var handler = new Handler();
        var selector = new OpenAIStoryLedStopSelector(new HttpClient(handler),
            new() { Enabled = true, ApiKey = "test", Model = "test" },
            [new EvidenceProvider(article)], TimeProvider.System);
        var result = await selector.SelectAsync(Command, Pool, 3, default);
        Check(result.Status.Contains("Wikipedia matches: 1"), "Report actual evidence matches.");
        Check(handler.Request!.Contains("A sourced historical passage."), "Matched evidence must reach selection.");
        var unavailable = new OpenAIStoryLedStopSelector(new HttpClient(new Handler()),
            new() { Enabled = true, ApiKey = "test", Model = "test" },
            [new EvidenceProvider(null)], TimeProvider.System);
        var degraded = await unavailable.SelectAsync(Command, Pool, 3, default);
        Check(degraded.Stops.Count == 2 && degraded.Status.Contains("Wikipedia matches: 0"), "Wikipedia failure must preserve selection from sourced Google candidates.");
    }

    public static async Task PlannerIntegration()
    {
        var router = new Router();
        var planner = new MockWalkPlanner(router, new Discovery(), Selector(new Handler { Ids = ["c", "b", "a"] }));
        var session = await planner.PlanWalkAsync(Command with { AvailableMinutes = 20 }, default);
        Check(router.Calls == 2, "Over-budget route must get only one reduction attempt.");
        Check(session.Stops.Count == 2, "Remove lower-priority stops.");
        Check(session.Stops.All(stop => stop.StopId != "a"), "Retain model priority when reducing.");
        Check(session.EstimatedDurationMinutes == 40, "Do not cap the actual route estimate.");
        Check(session.RouteSummary.Contains("exceeds"), "Disclose remaining time overrun.");
        Check(session.Stops.All(stop => stop.Narration == "Existing narration." && stop.RequiredAttribution.Contains("Google Maps")),
            "Preserve arrival narration and source attribution.");
        Check(session.Route.Provider == "GoogleRoutes", "Routing remains with supplied Google provider.");
        var fallback = await new MockWalkPlanner(new Router(), new Discovery(), Selector(new Handler { Malformed = true }))
            .PlanWalkAsync(Command, default);
        Check(fallback.Stops.Count >= 2 && fallback.RouteSummary.Contains("fallback"), "Keep walk creation functional.");
        var disabledHandler = new Handler();
        await new MockWalkPlanner(new Router(), new Discovery(), Selector(disabledHandler, false)).PlanWalkAsync(Command, default);
        Check(disabledHandler.Request is null, "Flag-off must not call OpenAI.");
    }

    private sealed class Handler : HttpMessageHandler
    {
        public string[] Ids { get; init; } = ["a", "b"];
        public string Status { get; init; } = "completed";
        public HttpStatusCode Code { get; init; } = HttpStatusCode.OK;
        public bool Malformed { get; init; }
        public bool Delay { get; init; }
        public string? Request { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Request = await request.Content!.ReadAsStringAsync(cancellationToken);
            if (Delay) await Task.Delay(Timeout.Infinite, cancellationToken);
            var json = Malformed ? "{}" : JsonSerializer.Serialize(new
            {
                status = Status,
                output = new[] { new { type = "message", content = new[] { new { type = "output_text",
                    text = JsonSerializer.Serialize(new { stopIds = Ids }) } } } }
            });
            return new(Code) { Content = new StringContent(json, Encoding.UTF8, "application/json") };
        }
    }
    private sealed class Discovery : ILocalDiscoveryProvider
    {
        public Task<IReadOnlyList<WalkStop>> FindStopsAsync(CreateWalkCommand command, CancellationToken cancellationToken) => Task.FromResult<IReadOnlyList<WalkStop>>(Pool);
        public Task<IReadOnlyList<WalkStop>> FindCandidateStopsAsync(CreateWalkCommand command, CancellationToken cancellationToken, int maximumStops = 30) => FindStopsAsync(command, cancellationToken);
    }
    private sealed class EvidenceProvider(LocationPlace? article) : ILocationContextProvider
    {
        public string Name => "Wikipedia";
        public Task<LocationContextProviderResult> GetContextAsync(LocationContextQuery query, CancellationToken cancellationToken)
            => article is null
                ? Task.FromException<LocationContextProviderResult>(new HttpRequestException("Unavailable"))
                : Task.FromResult(new LocationContextProviderResult(Name, true, [article], null, [], false, 1));
    }
    private sealed class Router : IWalkRouteProvider
    {
        public int Calls { get; private set; }
        public string ProviderName => "GoogleRoutes";
        public Task<WalkRoute> CreateRouteAsync(CreateWalkCommand command, IReadOnlyList<WalkStop> stops, CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(new WalkRoute("google-test", ProviderName, "1", DateTimeOffset.UtcNow,
                [command.StartingLocation, ..stops.Select(stop => stop.Location)],
                new(command.StartingLocation, stops[^1].Location), 1000, 30));
        }
    }
}
