using System.Net;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;
using Rover.Application.Drives;
using Rover.Application.LocationIntelligence;
using Rover.Application.Walks;
using Rover.Domain.Walks;
using Rover.Infrastructure.Walks;
using Rover.Application.Journeys;

internal static class ScenicDriveTests
{
    public static async Task StopStories()
    {
        var now = DateTimeOffset.UtcNow;
        var story = new AdaptiveRouteStory("story", "nearby", "end", "Stop history",
            RouteStoryIntent.HiddenHistory, "history", End, 0, 0,
            [new(AdaptiveStoryLength.Standard, 60, "end has documented history.", ["claim"])],
            [new("claim", "end has documented history.", ["source"], .9)],
            [new("source", "Archive", "History", "https://example.org/history", "Archive", now, .9)],
            .9, now.AddDays(1)) { AudienceSuitability = "family" };
        var researcher = new CapturingRouteResearcher(query => {
            Check(query.Question?.Text.Contains("end") == true && query.Question.StoryCount == 1,
                "Drive research must ask about the selected stop rather than reuse unrelated area stories.");
            return new([story], null);
        });
        var service = new DriveStopStoryService(new ScenicDriveService([new Places()], new Routes()), researcher, TimeProvider.System);
        var request = new DriveStopStoryRequest(End, "Sanremo", "end");
        var result = await service.CreateAsync(request, default);
        Check(result.ResearchStatus == "ready" && result.PlaceId == "end" && result.SourceReferences.Count == 1, "Drive story must preserve verified identity and sources.");
        Check(result.ExpiresUtc <= DateTimeOffset.UtcNow.AddHours(12), "Prepared stories must expire within the trip window.");
        foreach (var invalid in new[] { request with { PlaceId = "forged" }, request with { Location = Origin },
            request with { Query = "" }, request with { Location = new(double.NaN, 0) } })
        {
            try { await service.CreateAsync(invalid, default); throw new Exception("Invalid stop accepted."); }
            catch (ArgumentException) { }
        }
        var empty = new DriveStopStoryService(new ScenicDriveService([new Places()], new Routes()),
            new CapturingRouteResearcher(_ => new([], null)), TimeProvider.System);
        Check((await empty.CreateAsync(request, default)).ShortSpokenNarration == "", "No research must remain silent.");
        var sensitive = new DriveStopStoryService(new ScenicDriveService([new Places()], new Routes()),
            new CapturingRouteResearcher(_ => new([story with { AudienceSuitability = "sensitive" }], null)), TimeProvider.System);
        Check((await sensitive.CreateAsync(request, default)).ShortSpokenNarration == "", "Sensitive stories must not autoplay.");
    }
    static readonly GeoLocation Origin = new(43.7, 7.25);
    static readonly GeoLocation End = new(43.82, 7.7);
    static DriveRequest Request(bool back = false, int budget = 180) =>
        new(Origin, new("Sanremo Italy", "end", true), back, budget, 15, ["History", "Nature"]);
    static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }

    public static async Task BudgetAndReturn()
    {
        var provider = new Places();
        var routing = new Routes();
        var service = new ScenicDriveService([provider], routing);
        var plan = await service.PlanAsync(Request(true), default);
        Check(plan.ReturnToStart && routing.Calls.Last().Last() == Origin, "Return must route back to origin.");
        Check(plan.Stops.Count == 2, "Expected two distinct optional stops.");
        Check(plan.StopMinutes == 45 && plan.BufferMinutes == 12 && plan.TotalMinutes == 137, "Budget must include destination, stops, return and buffer.");
        Check(plan.FitsBudget, "Within budget.");
        Check(routing.Calls.Count == 4, "Bounded route requests.");
        Check(provider.Queries[0].RadiusMeters == 1_000_000 && provider.Queries.Skip(1).All(q => q.RadiusMeters == 3000), "Search radius must suit destination versus nearby stops.");

        routing = new Routes();
        var shortPlan = await new ScenicDriveService([new Places()], routing).PlanAsync(Request(true, 60), default);
        Check(!shortPlan.FitsBudget && shortPlan.Stops.Count == 0 && shortPlan.TotalMinutes == 84, "Overbudget must not invent a faster route or optional stops.");
        Check(routing.Calls.Count == 2, "Skip discovery for overbudget routes.");
        var oneWay = await new ScenicDriveService([new Places()], new Routes()).PlanAsync(Request(false), default);
        Check(!oneWay.ReturnToStart && oneWay.Route.DrivingMinutes == 60, "One way differs from return route.");
    }
    public static async Task ValidationAndFailures()
    {
        Check(!ScenicDriveService.ValidRequest(Request() with { Origin = new(double.NaN, 2) }), "Reject NaN.");
        Check(!ScenicDriveService.ValidRequest(Request() with { AvailableMinutes = 0 }), "Reject invalid budget.");
        Check(!ScenicDriveService.ValidRequest(Request() with { MinutesPerStop = 61 }), "Reject unbounded stops.");
        Check(!ScenicDriveService.ValidRequest(Request() with { Interests = ["invented"] }), "Reject arbitrary query interests.");
        Check(!ScenicDriveService.ValidRequest(Request() with { Destination = null! }), "Destination required.");
        var routing = new Routes();
        try {
            await new ScenicDriveService([new Places()], routing).PlanAsync(Request() with { Destination = new("Sanremo", "forged") }, default);
            throw new Exception("Forged place accepted.");
        } catch (ArgumentException) { }
        Check(routing.Calls.Count == 0, "Unverified destination must never reach road routing.");
        routing.Fail = true;
        try {
            await new ScenicDriveService([new Places()], routing).PlanAsync(Request(), default);
            throw new Exception("Expected route failure.");
        } catch (DrivingUnavailableException) { }
        var noInterests = await new ScenicDriveService([new Places()], new Routes()).PlanAsync(Request() with { Interests = [] }, default);
        Check(noInterests.Stops.Count == 0 && noInterests.StopMinutes == 15, "No interests means direct trip with destination visit.");
        var detours = new Routes { ExpensiveDetours = true };
        var direct = await new ScenicDriveService([new Places()], detours).PlanAsync(Request(false, 90), default);
        Check(direct.Stops.Count == 0 && direct.FitsBudget, "Reject detours exceeding budget.");
    }
    public static async Task DrivingWireContract()
    {
        var handler = new Handler();
        var provider = new GoogleDrivingRouteProvider(new Factory(handler),
            Options.Create(new GoogleRoutesOptions { ApiKey = "test", Timeout = TimeSpan.FromSeconds(2) }));
        var route = await provider.RouteAsync(Origin, [End, Origin], default, new(PreferLocalRoads: true, AvoidTolls: true));
        using var payload = JsonDocument.Parse(handler.Body!);
        Check(payload.RootElement.GetProperty("travelMode").GetString() == "DRIVE", "Must use driving, never walking.");
        Check(payload.RootElement.GetProperty("routingPreference").GetString() == "TRAFFIC_AWARE", "Traffic-aware estimate.");
        Check(payload.RootElement.GetProperty("intermediates").GetArrayLength() == 1, "Return destination is intermediate.");
        Check(payload.RootElement.GetProperty("routeModifiers").GetProperty("avoidHighways").GetBoolean(), "Local-road preference must reach Google.");
        Check(payload.RootElement.GetProperty("routeModifiers").GetProperty("avoidTolls").GetBoolean(), "Toll preference must reach Google.");
        Check(route.DrivingMinutes == 11 && route.Geometry[0].Latitude == 43.7 && route.Geometry[0].Longitude == 7.25, "Parse duration ceiling and GeoJSON coordinate order.");
        handler.Response = "{\"routes\":[]}";
        await MustFail(provider);
        handler.Response = "{\"routes\":[{\"duration\":\"NaNs\"}]}";
        await MustFail(provider);
        handler.Response = "{}";
        await MustFail(provider);
        handler.Status = HttpStatusCode.BadRequest;
        await MustFail(provider);
        var missingKey = new GoogleDrivingRouteProvider(new Factory(handler), Options.Create(new GoogleRoutesOptions()));
        await MustFail(missingKey);
    }
    public static async Task ExpandedInterests()
    {
        var places = new Places();
        var routes = new Routes();
        var interests = new[] { "scenic", "nature", "history", "towns", "food", "outdoors",
            "attractions", "wildlife", "family", "shopping", "relaxation", "art" };
        var request = Request(false, 360) with { Interests = interests, MaxOptionalStops = 6,
            Preferences = new(PreferLocalRoads: true, AvoidTolls: true, IncludeRestStops: true, IncludeChargingStops: true) };
        var plan = await new ScenicDriveService([places], routes).PlanAsync(request, default);
        Check(plan.Stops.Count > 2 && plan.Stops.Count <= 6 && plan.FitsBudget, "Use spare budget for more than two optional stops.");
        Check(interests.All(i => places.Queries.Any(q => q.RecognizedText == DriveInterestCatalog.Queries[i])), "Every selected category must be searched.");
        Check(places.Queries.Any(q => q.RecognizedText == "rest area") &&
            places.Queries.Any(q => q.RecognizedText == "electric vehicle charging station"), "Practical needs reach discovery.");
        Check(routes.Preferences.All(p => p == request.Preferences) && plan.Preferences == request.Preferences, "Preferences must survive every detour and response.");
        Check(routes.Calls.Count <= 18, "Bound costly road requests.");
        Check(ScenicDriveService.ValidRequest(request with { Interests = ["nature.lakes", "history.castles", "family.playgrounds"] }), "Accept specific subcategories.");
        Check(!ScenicDriveService.ValidRequest(request with { Interests = ["nature.made_up"] }), "Reject invented category keys.");
        Check(!ScenicDriveService.ValidRequest(request with { Preferences = null! }), "Reject null preferences.");
        Check(!ScenicDriveService.ValidRequest(request with { MaxOptionalStops = 99 }), "Reject unbounded itineraries.");
        Check(Request().MaxOptionalStops == 2, "Older apps retain their navigation waypoint limit.");
        Check(!ScenicDriveService.ValidRequest(request with { Preferences = new(MaxDetourMinutes: 0) }), "Validate detour cap.");
        var tight = await new ScenicDriveService([new Places()], new Routes()).PlanAsync(
            request with { Preferences = new(MaxDetourMinutes: 5) }, default);
        Check(tight.Stops.Count == 0, "Respect detour cap even when overall time is generous.");
        var search = await new ScenicDriveService([new Places()], new Routes()).SearchAsync("town", Origin, default);
        Check(search.Warnings.Count == 0, "Do not show unused-provider configuration warnings.");
    }
    static async Task MustFail(IDrivingRouteProvider provider)
    {
        try { await provider.RouteAsync(Origin, [End], default); throw new Exception("Driving provider silently fell back."); }
        catch (DrivingUnavailableException) { }
    }
    sealed class Places : ICandidateObservationSearchProvider
    {
        public List<CandidateObservationQuery> Queries { get; } = [];
        public Task<CandidateObservationSearchResult> SearchAsync(CandidateObservationQuery query, CancellationToken ct)
        {
            Queries.Add(query);
            var isDestination = query.RadiusMeters > 50000;
            var id = isDestination ? "end" : query.RecognizedText;
            var point = isDestination ? End : query.UserLocation;
            var source = new LocationSource("Test", id, "https://example.com", "Test source", null, DateTimeOffset.UtcNow, 1);
            var place = new LocationPlace(id, id, point, "Address", [], null, [], [source],
                new Dictionary<string, string>(), null, null, null, null, 1, 1, [], [], null, null, DateTimeOffset.UtcNow);
            return Task.FromResult(new CandidateObservationSearchResult("Test", [place], ["Mapbox business search is not configured."]));
        }
    }
    sealed class Routes : IDrivingRouteProvider
    {
        public List<GeoLocation[]> Calls { get; } = [];
        public List<DrivePreferences?> Preferences { get; } = [];
        public bool Fail { get; set; }
        public bool ExpensiveDetours { get; set; }
        public Task<DrivingRoute> RouteAsync(GeoLocation origin, IReadOnlyList<GeoLocation> visits, CancellationToken ct, DrivePreferences? preferences = null)
        {
            Calls.Add(visits.ToArray());
            Preferences.Add(preferences);
            if (Fail) throw new DrivingUnavailableException("No route");
            var back = visits[^1] == Origin;
            var count = visits.Count - (back ? 1 : 0) - 1;
            var minutes = (back ? 60 : 40) + count * (ExpensiveDetours ? 100 : 10);
            return Task.FromResult(new DrivingRoute(minutes, minutes * 500, [origin, End]));
        }
    }
    sealed class Factory(HttpMessageHandler handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name) => new(handler, false);
    }
    sealed class Handler : HttpMessageHandler
    {
        public string? Body;
        public HttpStatusCode Status = HttpStatusCode.OK;
        public string Response = """{"routes":[{"duration":"601s","distanceMeters":10000,"polyline":{"geoJsonLinestring":{"type":"LineString","coordinates":[[7.25,43.7],[7.7,43.82]]}}}]}""";
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Body = await request.Content!.ReadAsStringAsync(ct);
            return new(Status) { Content = new StringContent(Response, Encoding.UTF8, "application/json") };
        }
    }
}
