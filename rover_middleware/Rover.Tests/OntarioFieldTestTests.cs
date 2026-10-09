using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using Rover.Application.LocationIntelligence;
using Rover.Application.Journeys;
using Rover.Application.Walks;
using Rover.Domain.Walks;
using Rover.Infrastructure.Beta;
using Rover.Infrastructure.LocationIntelligence;
using Rover.Infrastructure.Journeys;
using Rover.Infrastructure.Walks;
using Rover.Api.Mapping;

internal static class OntarioFieldTestTests
{
    private static readonly Guid Tester = Guid.Parse("f8cf7c6e-86d3-4a6f-8da2-1a0e13a1340c");
    private static readonly GeoLocation Toronto = new(43.650, -79.370);
    private static OntarioFieldTestOptions Settings()
    {
        var settings = new OntarioFieldTestOptions();
        new ConfigurationBuilder().AddJsonFile(Path.GetFullPath("Rover.Api/appsettings.json")).Build()
            .GetSection("Rover:OntarioFieldTesting").Bind(settings);
        return settings;
    }
    private static OntarioFieldTestOptions Enroll()
    {
        var settings = Settings();
        settings.Enabled = true;
        settings.AllowAllBetaTesters = false;
        foreach (var market in settings.Markets.Values)
        { market.TesterProfileIds = [Tester]; market.IncludeExistingHeritageSources = false; market.Areas = []; }
        return settings;
    }
    private static LocationContextQuery Query(Guid? profile = null, GeoLocation? point = null, string[]? interests = null) =>
        new(point ?? Toronto, 1500, null, profile, [], interests ?? ["history"]);
    private static OntarioFieldTestProvider Provider(OntarioFieldTestOptions options, Handler handler, Recorder recorder)
    {
        var factory = new Factory(handler);
        var cache = new InMemoryLocationContextCache(TimeProvider.System);
        return new(options, new(factory, cache, TimeProvider.System, recorder), factory, cache, TimeProvider.System, recorder);
    }

    public static async Task Gates()
    {
        var settings = Settings();
        Check(settings.Enabled && settings.AllowAllBetaTesters
            && settings.Markets.Keys.Order().SequenceEqual(new[] { "milton", "toronto", "waterdown" }), "The requested markets are enabled for existing beta testers.");
        Check(settings.Markets.Values.All(m => m.TesterProfileIds.Length == 0 && m.Areas.All(a => a.IsValid)), "No default testers; valid bounded areas.");
        settings.Enabled = false;
        settings.AllowAllBetaTesters = false;
        foreach (var market in settings.Markets.Values) market.Areas = [];
        using var handler = new Handler();
        var provider = Provider(settings, handler, new());
        await provider.GetContextAsync(Query(Tester), default);
        settings.Enabled = true;
        await provider.GetContextAsync(Query(Tester), default);
        settings.Markets["toronto"].TesterProfileIds = [Tester];
        settings.Markets["toronto"].IncludeExistingHeritageSources = false;
        foreach (var query in new[] { Query(), Query(Guid.NewGuid()), Query(Tester, new(44.7, -79.4)), Query(Tester, interests: ["food"]) })
            Check((await provider.GetContextAsync(query, default)).Places.Count == 0, "Nonparticipants, other areas and food-only preferences are unaffected.");
        Check(handler.Calls == 0, "Disabled and ineligible callers make no provider requests.");
        await provider.GetContextAsync(Query(Tester), default);
        Check(handler.Calls == 1, "Enrolled tester activates only the eligible market.");
        settings.Markets["toronto"].TesterProfileIds = [];
        Check((await provider.GetContextAsync(Query(Tester), default)).Places.Count == 0 && handler.Calls == 1, "Revocation is checked before cache reuse.");
    }

    public static async Task CoordinatesEvidenceAndCaching()
    {
        var settings = Enroll();
        var recorder = new Recorder();
        using var handler = new Handler { Features = [Feature(1), Feature(1), Feature(2, lat: 43.8), Feature(3, lon: 43.65, lat: -79.37),
            Feature(4, description: ""), Feature(5, point: false)] };
        var provider = Provider(settings, handler, recorder);
        var result = await provider.GetContextAsync(Query(Tester), default);
        Check(result.Places.Count == 2 && result.Places.All(p => p.Coordinates == Toronto), "Retain only actual WGS84 points in the configured area.");
        Check(result.Places[0].Facts.Any(f => f.IsSuitableForNarration && RouteStoryEvidence.Priority(f) > 0), "Detailed municipal evidence supports a grounded narrative.");
        Check(result.Places.Single(p => p.Name == "4 Main Street").Facts.All(f => !f.IsSuitableForNarration), "Register membership alone is not a story.");
        Check(result.Places.All(p => p.SourceReferences.All(s => s.SourceUrl!.Contains("objectIds=") && s.Attribution.Contains("Licence") && s.License!.StartsWith("https://"))), "Carry record-level provenance and attribution.");
        await Task.WhenAll(Enumerable.Range(0, 6).Select(_ => provider.GetContextAsync(Query(Tester), default)));
        Check(handler.Calls == 1, "Concurrent tester reads reuse municipal discovery.");
        var architecture = await provider.GetContextAsync(Query(Tester, interests: ["architecture"]), default);
        Check(architecture.Places.All(p => p.Categories.SequenceEqual(new[] { "architecture" })), "Cached evidence is relabelled only with matching requested categories.");
        Check(handler.LastQuery!.Contains("outSR=4326") && handler.LastQuery.Contains("inSR=4326") && handler.LastQuery.Contains("resultRecordCount=200"), "Explicit projection and bounded pagination.");
        var audit = recorder.Events.Single(e => e.Kind == "municipal-discovery");
        Check(audit.Discovered == 6 && audit.Duplicates == 1 && audit.Excluded == 3 && audit.Evidence == 2, "Counts distinguish excluded, duplicate and evidenced records.");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try { await provider.GetContextAsync(Query(Tester), cancelled.Token); throw new Exception("Cancellation lost"); }
        catch (OperationCanceledException) { }
    }

    public static async Task PaginationAndFailures()
    {
        foreach (var mode in new[] { "error", "http", "projection", "polygon" })
        {
            using var handler = new Handler { Mode = mode };
            var provider = Provider(Enroll(), handler, new());
            var result = await provider.GetContextAsync(Query(Tester), default);
            Check(result.Places.Count == 0 && result.Warnings.Count > 0, "Reject errors and incompatible geometry.");
            await provider.GetContextAsync(Query(Tester), default);
            Check(handler.Calls == 1, "Negative caching bounds failed-provider retries.");
        }
        using var pages = new Handler { Mode = "pages" };
        var paged = await Provider(Enroll(), pages, new()).GetContextAsync(Query(Tester), default);
        Check(pages.Calls == 2 && paged.Places.Count == 2 && pages.LastQuery!.Contains("resultOffset=200"), "Read subsequent pages deterministically.");
        var options = Enroll();
        options.Markets["toronto"].Datasets[0].Endpoint = "https://127.0.0.1/private";
        using var unsafeHandler = new Handler();
        var unsafeResult = await Provider(options, unsafeHandler, new()).GetContextAsync(Query(Tester), default);
        Check(unsafeHandler.Calls == 0 && unsafeResult.Warnings.Count > 0, "No requests to unreviewed endpoints.");
        Check(!options.Match(Tester, new(double.NaN, -79.37)).HasValue, "Nonfinite locations cannot enroll.");

        var outages = Enroll();
        outages.Markets["toronto"].IncludeExistingHeritageSources = true;
        using var outageHandler = new Handler();
        var outageProvider = Provider(outages, outageHandler, new());
        await outageProvider.GetContextAsync(Query(Tester), default);
        await outageProvider.GetContextAsync(Query(Tester, new(43.651, -79.371)), default);
        Check(outageHandler.CallsByHost["en.wikipedia.org"] == 1 && outageHandler.CallsByHost["query.wikidata.org"] == 1,
            "Failed companion responses enter a shared market cooldown across different route sections.");
    }

    public static async Task IndependentMarketsAndSparseJourneys()
    {
        var options = Enroll();
        using var handler = new Handler();
        var provider = Provider(options, handler, new());
        var normal = new OrdinaryDiscovery();
        var discovery = new OntarioLocalDiscoveryProvider(normal, provider, options);
        var routeProvider = new MockWalkRouteProvider();
        foreach (var minutes in new[] { 20, 60, 90 })
        {
            var command = new CreateWalkCommand(Toronto, minutes, ["history"], WalkingPace.Standard, []) { ProfileId = Tester };
            var walk = await new MockWalkPlanner(routeProvider, discovery).PlanWalkAsync(command, default);
            Check(walk.Stops.Count >= 2 && walk.ProfileId == Tester && walk.Interests.Contains("history"), "Short and long walks preserve identity, interests and real candidates.");
        }
        var baseCommand = new CreateWalkCommand(Toronto, 60, ["food"], WalkingPace.Standard, []) { ProfileId = Tester };
        Check((await discovery.DiscoverForPlanningAsync(baseCommand, default, 12)).Stops.SequenceEqual(normal.Stops), "No historical stops on a food-only walk.");
        var milton = options.Markets["milton"];
        Check(!milton.Datasets[0].Enabled, "Unreachable Milton municipal endpoint is not enabled prematurely.");
        var sparse = await discovery.DiscoverForPlanningAsync(baseCommand with { StartingLocation = new(43.513, -79.882), Interests = ["history"] }, default, 12);
        Check(sparse.Stops.SequenceEqual(normal.Stops), "Sparse municipal data preserves existing discovery.");
        Check(options.Match(Tester, new(43.334, -79.892))?.Key == "waterdown"
            && options.Match(Tester, new(43.513, -79.882))?.Key == "milton", "Market boundaries operate independently.");
        options.Markets["toronto"].Enabled = false;
        Check(options.Match(Tester, Toronto) is null && options.Match(Tester, new(43.334, -79.892)) is not null, "Independent kill switches.");
    }

    public static Task Feedback()
    {
        var good = new OntarioFieldTestFeedback(Tester, 5, 4, 4, 3, "played", "Helpful route.");
        Check(good.IsValid && !(good with { StoryAccuracy = 0 }).IsValid && !(good with { VoiceQuality = 6 }).IsValid
            && !(good with { NarrationResult = "invented" }).IsValid && !(good with { Comments = new string('x', 1001) }).IsValid, "Structured feedback validates ratings and outcomes.");
        var options = Enroll();
        options.ReportDirectory = Path.Combine(Path.GetTempPath(), "ontario-test-" + Guid.NewGuid().ToString("N"));
        new FileOntarioFieldTestRecorder(options, TimeProvider.System, NullLogger<FileOntarioFieldTestRecorder>.Instance)
            .Record(new("toronto", "tester-feedback", "submitted", WalkSessionId: "private-session-id", Feedback: good));
        var text = File.ReadAllText(Directory.GetFiles(options.ReportDirectory).Single());
        Check(text.Contains("storyAccuracy") && !text.Contains(Tester.ToString()) && !text.Contains("private-session-id"), "Stored feedback excludes raw identity and tracks.");
        Check(text.Contains("\"geographicProfileId\":\"WALK-CA-ON-TOR-001\""), "Feedback carries the stable geographic ID, not a personal profile ID.");
        foreach (var file in Directory.GetFiles(options.ReportDirectory)) File.Delete(file);
        Directory.Delete(options.ReportDirectory);
        return Task.CompletedTask;
    }

    public static async Task GeographicProfilesAndTravel()
    {
        var settings = Settings();
        settings.Validate();
        var expected = new Dictionary<string, (string Id, int Radius)>
        {
            ["waterdown"] = ("WALK-CA-ON-WAT-001", 8000),
            ["toronto"] = ("WALK-CA-ON-TOR-001", 10000),
            ["milton"] = ("WALK-CA-ON-MIL-001", 8000)
        };
        foreach (var (key, value) in expected)
        {
            var market = settings.Markets[key];
            Check(market.Enabled && market.GeographicProfileId == value.Id && market.SearchRadiusMeters == value.Radius
                && market.IncludeExistingHeritageSources && market.HasValidGeography, "Stored geographic profiles have the requested IDs and discovery radii.");
            Check(Settings().Markets[key].GeographicProfileId == value.Id, "Profile IDs survive configuration reloads.");
            Check(settings.Match(null, market.Center!)?.Value.GeographicProfileId == value.Id
                && settings.Match(Guid.NewGuid(), market.Center!)?.Value.GeographicProfileId == value.Id,
                "All existing beta callers are geographically eligible without enrollment IDs.");
            Check(!Guid.TryParse(value.Id, out _), "Geographic IDs are separate from personal GUIDs.");
        }
        settings.AllowAllBetaTesters = false;
        settings.Markets["waterdown"].TesterProfileIds = [Tester];
        Check(settings.Match(Tester, settings.Markets["toronto"].Center!)?.Key == "toronto",
            "An enrolled Waterdown tester may visit another enabled region.");
        Check(settings.Match(Tester, new(52.08, 4.31)) is null, "Travelling outside Ontario uses normal discovery, not home-region data.");
        settings.AllowAllBetaTesters = true;
        var recorder = new Recorder();
        var service = new WalkSessionService(new MockWalkPlanner(new MockWalkRouteProvider(), new OrdinaryDiscovery()),
            new InMemoryWalkSessionRepository(), TimeProvider.System, ontario: settings, fieldTests: recorder);
        var command = new CreateWalkCommand(Toronto, 60, ["history"], WalkingPace.Standard, []) { ProfileId = Tester };
        var walk = await service.CreateAsync(command, default);
        Check(walk.GeographicProfileId == expected["toronto"].Id && walk.ProfileId == Tester
            && walk.ToResponse().GeographicProfileId == expected["toronto"].Id, "Journey diagnostics keep separate geographic and personal identities.");
        walk.Start(DateTimeOffset.UtcNow);
        walk.RecordLocation(new(52.08, 4.31), DateTimeOffset.UtcNow, null, 10, 40, true, 100, null);
        Check(settings.ForJourney(walk)?.Value.GeographicProfileId == expected["toronto"].Id,
            "Journey reporting retains its original profile when the tester leaves the region.");
        Check(recorder.Events.Single(e => e.Kind == "journey").GeographicProfileId == expected["toronto"].Id,
            "Journey telemetry carries the geographic ID.");
        var outside = await service.CreateAsync(command with { StartingLocation = new(52.08, 4.31) }, default);
        Check(outside.GeographicProfileId is null && outside.Stops.Count > 0, "An out-of-region walk is not blocked.");

        settings.Markets["milton"].GeographicProfileId = expected["toronto"].Id;
        try { settings.Validate(); throw new Exception("Duplicate IDs were accepted"); }
        catch (InvalidOperationException) { }
        settings = Settings();
        settings.Markets["toronto"].SearchRadiusMeters = 10001;
        try { settings.Validate(); throw new Exception("Unbounded radius was accepted"); }
        catch (InvalidOperationException) { }
    }

    public static async Task RegionalRadiusAndLocalStops()
    {
        var settings = Enroll();
        using var handler = new Handler { Features = [Feature(1), Feature(2, lat: 43.707), Feature(3, lat: 43.76)] };
        var provider = Provider(settings, handler, new());
        var result = await provider.GetContextAsync(Query(Tester) with { RadiusMeters = 10000 }, default);
        Check(result.Places.Count == 2 && result.Places.Any(p => p.Name == "2 Main Street"),
            "Regional discovery retains a verified point beyond the old 3 km cap and downtown box.");
        Check(handler.LastQuery!.Contains("distance=10000") && handler.LastQuery.Contains("geometryType=esriGeometryPoint"),
            "The configured 10 km radius reaches the municipal query.");
        Check((await provider.GetContextAsync(Query(Tester), default)).Places.Count == 1,
            "A smaller route-story query remains near the route, even with a regional cache.");
        var discovery = new OntarioLocalDiscoveryProvider(new OrdinaryDiscovery(), provider, settings);
        var stops = await discovery.FindStopsAsync(new(Toronto, 20, ["history"], WalkingPace.Standard, []) { ProfileId = Tester }, default);
        Check(!stops.Any(stop => stop.Name == "2 Main Street"), "Wide discovery does not inject distant stops into a short walk.");

        var cachedCalls = handler.Calls;
        settings.Markets["toronto"].SearchRadiusMeters = 8000;
        await provider.GetContextAsync(Query(Tester), default);
        Check(handler.Calls == cachedCalls + 1 && handler.LastQuery!.Contains("distance=8000"),
            "Changing backend geography invalidates the municipal cache and applies the 8 km radius.");

        using var federalHandler = new Handler();
        var federal = new ParksCanadaHeritageLocationContextProvider(new Factory(federalHandler),
            new InMemoryLocationContextCache(TimeProvider.System), TimeProvider.System,
            new LocationProviderOptions { Enabled = true }, 10000);
        await federal.GetContextAsync(Query(Tester) with { RadiusMeters = 10000 }, default);
        Check(federalHandler.LastQuery!.Contains("distance=10000"), "The federal companion honors the pilot radius without changing its global default.");
    }

    public static async Task EnrichmentAndAutomaticStoryIdentity()
    {
        var options = Enroll();
        using var handler = new Handler();
        var provider = Provider(options, handler, new());
        var match = new WalkStop("existing-hall", 1, "1 Main Street", Toronto,
            "A public landmark", "Arrival at the hall.", "history", ContentType.History,
            ContentSource.LocalRecommendation, 4, 100, 30, address: "1 Main Street",
            discoveryProviderName: "Existing", providerPlaceId: "stable-provider-id", sourceUrl: "https://example.org/hall")
            { IsDestination = true };
        var ordinary = new OrdinaryDiscovery { Stops = [match] };
        var discovery = new OntarioLocalDiscoveryProvider(ordinary, provider, options);
        var command = new CreateWalkCommand(Toronto, 60, ["history"], WalkingPace.Standard, []) { ProfileId = Tester };
        var result = await discovery.DiscoverForPlanningAsync(command, default, 12);
        var stop = result.Stops.Single();
        Check(stop.StopId == match.StopId && stop.Location == match.Location && stop.IsDestination
            && stop.ProviderPlaceId == match.ProviderPlaceId && stop.SourceUrl == match.SourceUrl,
            "Matching municipal evidence preserves existing POI identity and routing coordinates.");
        Check(stop.Narration.StartsWith(match.Narration) && stop.Narration.Contains("1880")
            && stop.RequiredAttribution.Any(a => a.Contains("objectIds=1")), "Enrich one stop with cited history rather than duplicating it.");

        var session = await new MockWalkPlanner(new MockWalkRouteProvider(), new OrdinaryDiscovery()).PlanWalkAsync(command, default);
        var walks = new InMemoryWalkSessionRepository();
        await walks.AddAsync(session, default);
        var phase15 = new Phase15Options { Enabled = true, CorridorEnabled = true };
        var plans = new RouteStoryPlanService(phase15, new DeterministicRouteStoryPlanner(phase15),
            new InMemoryRouteStoryPlanRepository(), TimeProvider.System);
        var context = new RecordingLocationStoryContextService();
        var phase16 = new Phase16Options { Enabled = true, JourneyCollectionsEnabled = true };
        var service = new AdaptiveRouteStoryPackService(phase16, walks, plans, context,
            new InMemoryAdaptiveRouteStoryPackRepository(), new DeterministicStoryIntentClassifier(),
            new DeterministicAdaptiveStoryLengthSelector(phase16), TimeProvider.System);
        await service.GenerateAsync(session.WalkSessionId, new(null, "GeneralTraveller", "en", false), default);
        Check(context.Queries.Count > 0 && context.Queries.All(q => q.ProfileId == Tester
            && q.Interests.SequenceEqual(command.Interests)), "Automatic research inherits tester enrollment and interests without a supplied profile.");
        context.Queries.Clear();
        await service.GenerateAsync(session.WalkSessionId, new(Guid.NewGuid(), "GeneralTraveller", "en", true), default);
        Check(context.Queries.Count > 0 && context.Queries.All(q => q.ProfileId == Tester), "A supplied profile cannot replace the walk owner's enrollment.");
    }

    public static async Task Audit()
    {
        var settings = Settings();
        using var handler = new HttpClientHandler { AllowAutoRedirect = false };
        var recorder = new Recorder();
        var client = new OntarioMunicipalHeritageClient(new Factory(handler), new InMemoryLocationContextCache(TimeProvider.System), TimeProvider.System, recorder);
        foreach (var market in settings.Markets)
        {
            var area = market.Value.Areas[0];
            var center = market.Value.Center ?? new GeoLocation((area.North + area.South) / 2, (area.West + area.East) / 2);
            var catalog = new OntarioMarketOptions { GeographicProfileId = market.Value.GeographicProfileId,
                Center = market.Value.Center, Areas = market.Value.Areas, City = market.Value.City,
                SearchRadiusMeters = market.Value.SearchRadiusMeters, MaximumPlaces = 100 };
            foreach (var dataset in market.Value.Datasets)
            {
                var result = await client.FindAsync(market.Key, catalog, dataset, Query(Tester, center) with { RadiusMeters = catalog.SearchRadiusMeters }, default);
                Console.WriteLine(JsonSerializer.Serialize(new { market = market.Key, catalog.GeographicProfileId, dataset = dataset.Id, result.Enabled,
                    result.LatencyMilliseconds, result.Warnings, returnedSample = result.Places.Count,
                    narrativeEvidenceInSample = result.Places.Count(p => p.Facts.Any(f => f.IsSuitableForNarration)),
                    examples = result.Places.Take(2).Select(p => new { p.Name, p.Coordinates }) }));
            }
            var providerOptions = new LocationProviderOptions { Enabled = true, MaximumResults = 20, TimeoutSeconds = 6, CacheMinutes = 1440 };
            var factory = new Factory(handler);
            var cache = new InMemoryLocationContextCache(TimeProvider.System);
            ILocationContextProvider[] companions = [new WikipediaLocationContextProvider(factory, cache, TimeProvider.System, providerOptions),
                new WikidataLocationContextProvider(factory, cache, TimeProvider.System, providerOptions),
                new ParksCanadaHeritageLocationContextProvider(factory, cache, TimeProvider.System, providerOptions, catalog.SearchRadiusMeters)];
            foreach (var provider in companions)
            {
                var result = await provider.GetContextAsync(Query(Tester, center) with { RadiusMeters = market.Value.SearchRadiusMeters }, default);
                var inArea = result.Places.Where(p => market.Value.Contains(p.Coordinates)).ToArray();
                Console.WriteLine(JsonSerializer.Serialize(new { market = market.Key, source = provider.Name,
                    result.LatencyMilliseconds, result.Warnings, returned = result.Places.Count, inArea = inArea.Length,
                    narrativeEvidenceInSample = inArea.Count(p => p.Facts.Any(f => RouteStoryEvidence.Priority(f) > 0)),
                    examples = inArea.Take(2).Select(p => new { p.Name, p.Coordinates }) }));
            }
        }
        foreach (var entry in recorder.Events) Console.WriteLine(JsonSerializer.Serialize(entry));
    }

    private static object Feature(int id, double lat = 43.650, double lon = -79.370,
        string description = "Built in 1880 as a local community meeting hall.", bool point = true) => new
    { attributes = new { OBJECTID = id, ADDRESS = $"{id} Main Street", STATUS = "Listed", DETAILS = description }, geometry = point ? new { x = lon, y = lat } : null };
    private sealed class Recorder : IOntarioFieldTestRecorder
    {
        public List<OntarioFieldTestEvent> Events { get; } = [];
        public void Record(OntarioFieldTestEvent entry) => Events.Add(entry);
    }
    private sealed class Factory(HttpMessageHandler handler) : IHttpClientFactory
    {
        public HttpClient CreateClient(string name)
        {
            var client = new HttpClient(handler, false) { Timeout = TimeSpan.FromSeconds(10) };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("WalkaboutOntarioPilot/1.0");
            return client;
        }
    }
    private sealed class Handler : HttpMessageHandler
    {
        public int Calls;
        public Dictionary<string, int> CallsByHost { get; } = [];
        public string Mode = "";
        public string? LastQuery;
        public object[] Features = [Feature(1)];
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            var host = request.RequestUri!.Host;
            CallsByHost[host] = CallsByHost.GetValueOrDefault(host) + 1;
            LastQuery = request.RequestUri!.Query;
            if (Mode == "http") return Task.FromResult(new HttpResponseMessage(HttpStatusCode.TooManyRequests));
            var json = Mode == "error" ? "{\"error\":{\"code\":400}}" : JsonSerializer.Serialize(new
            {
                geometryType = Mode == "polygon" ? "esriGeometryPolygon" : "esriGeometryPoint",
                spatialReference = new { wkid = Mode == "projection" ? 3857 : 4326 },
                features = Mode == "pages" ? new[] { Feature(Calls) } : Features,
                exceededTransferLimit = Mode == "pages" && Calls == 1
            });
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json) });
        }
    }
    private sealed class OrdinaryDiscovery : ILocalDiscoveryProvider
    {
        public bool RequiresRealPlaces => true;
        public IReadOnlyList<WalkStop> Stops { get; init; } = Enumerable.Range(1, 3).Select(i => new WalkStop($"ordinary-{i}", i,
            $"Cafe {i}", new(43.65 + .001 * i, -79.37), "A cafe", "A cafe", "food", ContentType.FoodAndDrink,
            ContentSource.LocalRecommendation, 3, 50, 30)).ToArray();
        public Task<IReadOnlyList<WalkStop>> FindStopsAsync(CreateWalkCommand command, CancellationToken token) => Task.FromResult(Stops);
        public Task<IReadOnlyList<WalkStop>> FindCandidateStopsAsync(CreateWalkCommand command, CancellationToken token, int maximumStops = 30) => Task.FromResult(Stops);
    }
    private static void Check(bool valid, string message) { if (!valid) throw new Exception(message); }
}
