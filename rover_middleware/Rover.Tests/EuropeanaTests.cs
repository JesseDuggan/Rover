using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Rover.Application.Journeys;
using Rover.Application.LiveContext;
using Rover.Domain.Walks;
using Rover.Infrastructure.Journeys;

internal static class EuropeanaTests
{
    private const string Article = "https://en.wikipedia.org/wiki/Laan_van_Meerdervoort";
    private const string Item = "https://www.europeana.eu/item/123/view_1";
    private const string Preview = "https://api.europeana.eu/thumbnail/v3/200/820911931db3ccb20e1b7a022ee6dd33.jpg";
    private static EuropeanaArchiveClient Client(Handler handler, Clock? clock = null, string? key = "test-key", bool enabled = true) =>
        new(new Factory(handler), new EuropeanaOptions { ApiKey = key, Enabled = enabled, MinimumRequestInterval = TimeSpan.Zero },
            clock ?? new Clock(), NullLogger<EuropeanaArchiveClient>.Instance);

    public static async Task ConfigurationAndSources()
    {
        using var handler = new Handler();
        using var missing = Client(handler, key: null);
        using var disabled = Client(handler, enabled: false);
        Check((await missing.FindPicturesAsync(Article, default)).Images.Count == 0 &&
            (await disabled.FindPicturesAsync(Article, default)).Images.Count == 0 && handler.Calls == 0,
            "Absent key and kill switch leave Wikimedia unaffected, with no external calls.");
        using var client = Client(handler);
        foreach (var source in new[] { "http://localhost/private", "https://www.europeana.eu.evil.org/item/123/view_1",
            "https://user@www.europeana.eu/item/123/view_1", "https://www.europeana.eu:444/item/123/view_1",
            "https://www.europeana.eu/item/123/../private", "https://en.wikipedia.org/wiki/Category:History", "https://en.wikipedia.org/wiki/Museum" })
            Check((await client.FindPicturesAsync(source, default)).Images.Count == 0, "Reject arbitrary or ambiguous sources.");
        Check(handler.Calls == 0, "Rejected sources never contact providers.");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try { await client.FindPicturesAsync(Article, cancelled.Token); throw new Exception("Lost cancellation"); }
        catch (OperationCanceledException) { }
    }

    public static async Task RightsMatchingAndSecrets()
    {
        using var handler = new Handler();
        var good = Record();
        handler.Records = [good,
            Record("unrelated", title: "Canal in another city"),
            Record("restricted", rights: "http://rightsstatements.org/vocab/InC/1.0/"),
            Record("unsafe", preview: "http://127.0.0.1/private.jpg"),
            Record("no-distribute", noDistribute: true),
            Record("no-credit", creator: "")];
        using var client = Client(handler);
        var result = await client.FindPicturesAsync(Article, default);
        Check(!result.Failed && result.Images.Count == 1, "Reject unrelated, restricted, unsafe, withheld and uncredited pictures.");
        var image = result.Images[0];
        Check(image.Provider == "Europeana" && image.IsArchive && !image.IsNearby && image.SourceUrl == Item
            && image.Caption == "Laan van Meerdervoort, The Hague (1910)"
            && image.Attribution == "Photographer - City Archive" && image.LicenseUrl == "https://creativecommons.org/licenses/by-sa/4.0/",
            "Preserve archival context, recorded date, creator, provider and rights.");
        Check(image.Url.Contains("/400/") && !image.Url.Contains("test-key"), "Use public thumbnails with no API credentials.");
        Check(handler.Key == "test-key" && !handler.Query!.Contains("test-key") && handler.Query.Contains("reusability=open")
            && handler.Query.Contains("title:\"Laan van Meerdervoort\""), "Authenticated, bounded exact-subject search.");
        Check(!JsonSerializer.Serialize(result).Contains("secret-echo"), "Never expose the response apikey or raw metadata.");
        await client.FindPicturesAsync(Article, default);
        Check(handler.Calls == 1, "Repeated visitors share cached metadata.");
        result = await client.FindPicturesAsync("https://www.europeana.eu/en/item/123/view_1", default);
        Check(result.Images.Count == 1 && handler.Query!.Contains("europeana_id:\"/123/view_1\""), "Cited archive URLs resolve the exact record.");
        handler.Records = [Record("other", rights: "https://creativecommons.org/licenses/by-nc/4.0/")];
        result = await client.FindPicturesAsync("https://www.europeana.eu/item/123/other", default);
        Check(result.Images.Count == 0, "Non-commercial licences are not treated as general reuse permission.");
        handler.Records = [Record("legacy", preview: "https://api.europeana.eu/thumbnail/v2/url.json?uri=https%3A%2F%2Farchive.example.org%2Fview.jpg&size=w200&type=IMAGE&wskey=secret-echo")];
        result = await client.FindPicturesAsync("https://www.europeana.eu/item/123/legacy", default);
        Check(result.Images.Count == 1 && result.Images[0].Url.EndsWith("&size=w400&type=IMAGE")
            && !result.Images[0].Url.Contains("secret-echo"), "Sanitize legacy thumbnail parameters instead of passing raw provider URLs.");
        var conflicting = Record("conflicting");
        conflicting["rights"] = new[] { "https://creativecommons.org/licenses/by/4.0/", "http://rightsstatements.org/vocab/InC/1.0/" };
        handler.Records = [conflicting];
        result = await client.FindPicturesAsync("https://www.europeana.eu/item/123/conflicting", default);
        Check(result.Images.Count == 0, "Do not guess which media conflicting rights apply to.");
        handler.Records = [Record("public", creator: "", rights: "http://creativecommons.org/publicdomain/mark/1.0/")];
        result = await client.FindPicturesAsync("https://www.europeana.eu/item/123/public", default);
        Check(result.Images.Count == 1 && result.Images[0].Attribution.StartsWith("Creator not recorded - "),
            "Public-domain records keep the holding institution's credit without inventing an author.");
    }

    public static async Task CooldownAndConcurrentVisitors()
    {
        using var handler = new Handler { Status = HttpStatusCode.TooManyRequests };
        var clock = new Clock();
        using var client = Client(handler, clock);
        Check((await client.FindPicturesAsync(Article, default)).Failed, "429 is a provider failure, not a cached absence of images.");
        Check((await client.FindPicturesAsync(Item, default)).Failed && handler.Calls == 1, "Cooldown covers other subjects and users too.");
        clock.Now = clock.Now.AddSeconds(119);
        await client.FindPicturesAsync(Article, default);
        Check(handler.Calls == 1, "Respect the provider Retry-After header.");
        clock.Now = clock.Now.AddSeconds(2);
        handler.Status = HttpStatusCode.OK;
        var results = await Task.WhenAll(Enumerable.Range(0, 10).Select(_ => client.FindPicturesAsync(Article, default)));
        Check(results.All(r => r.Images.Count == 1) && handler.Calls == 2, "Concurrent callers coalesce into one recovery request.");
        handler.Success = false;
        Check((await client.FindPicturesAsync(Item, default)).Failed, "HTTP 200 API errors stay failures.");
        clock.Now = clock.Now.AddMinutes(2);
        handler.Success = true;
        Check((await client.FindPicturesAsync(Item, default)).Images.Count == 1, "API error does not poison the cache.");
        clock.Now = clock.Now.AddMinutes(2);
        handler.Status = HttpStatusCode.Unauthorized;
        await client.FindPicturesAsync("https://en.wikipedia.org/wiki/Another_subject", default);
        var calls = handler.Calls;
        clock.Now = clock.Now.AddMinutes(2);
        await client.FindPicturesAsync("https://en.wikipedia.org/wiki/Third_subject", default);
        Check(handler.Calls == calls, "Invalid credentials use a longer cooldown without repeated attempts.");
    }

    public static async Task InterestsAndGeography()
    {
        using var handler = new Handler();
        using var client = Client(handler);
        var anchor = new GeoLocation(52.0834, 4.2911);
        var segment = new RouteStorySegment("area", 0, anchor, anchor, anchor, 0, 0, 0, 0, false, []);
        var query = new LocalRouteResearchQuery([segment], new ApproximateLiveLocation("The Hague", null, "Netherlands", null),
            [], ["food"], "en", [new("Laan van Meerdervoort", null, anchor)]);
        Check((await client.FindResearchLeadsAsync(query, [], default)).Count == 0 && handler.Calls == 0,
            "Food-only visitors are not pushed historical archive subjects.");
        Check((await client.FindResearchLeadsAsync(query with { Interests = ["history"],
            PublicPlaces = [new("Laan van Meerdervoort", null, new(40, 10))] }, [], default)).Count == 0 && handler.Calls == 0,
            "Off-route subjects never become archive leads.");
        var leads = await client.FindResearchLeadsAsync(query with { Interests = ["history"] }, [], default);
        Check(leads.Count == 1 && leads[0].SourceUrl == Item && handler.Query!.Contains("where:\"The Hague\""),
            "Search exact route subjects within their named locality; coordinates in archive records are not used.");
        using var other = Client(handler);
        var record = Record(title: "Laan van Meerdervoort");
        record["dcDescription"] = new[] { "A street view." };
        record["edmPlaceLabel"] = new[] { new { en = new[] { "Paris" } } };
        record["dataProvider"] = new[] { "The Hague" };
        handler.Records = [record];
        Check((await other.FindResearchLeadsAsync(query with { Interests = ["history"] }, [], default)).Count == 0,
            "A holding institution's city is not evidence of the depicted subject's location.");
    }

    public static async Task ImagePipelineFallback()
    {
        using var handler = new Handler();
        using var archive = Client(handler);
        using var service = new StoryImageService(new Factory(handler), NullLogger<StoryImageService>.Instance, archive);
        var result = await service.FindAsync(new([Article]), default);
        Check(result.Images.Count == 2 && result.Images[0].Provider == "Wikimedia Commons" && result.Images[1].IsArchive,
            "Keep existing Wikimedia pictures and add archive material to the same carousel contract.");
        result = await service.FindAsync(new([Item]), default);
        Check(result.Images.Count == 1 && result.Images[0].Provider == "Europeana", "Exact archive citations reach the picture API.");
        handler.Status = HttpStatusCode.ServiceUnavailable;
        result = await service.FindAsync(new(["https://en.wikipedia.org/wiki/Other_subject"]), default);
        Check(result.Status == "ready" && result.Images.Count == 1, "Europeana failure cannot hide existing pictures.");
    }

    public static async Task TimeoutsAndMalformedResponses()
    {
        using var handler = new Handler { Hang = true };
        var clock = new Clock();
        using var archive = Client(handler, clock);
        using var service = new StoryImageService(new Factory(handler), NullLogger<StoryImageService>.Instance, archive);
        var result = await service.FindAsync(new([Article]), default);
        Check(result.Status == "ready" && result.Images.Count == 1, "A timed-out archive still returns Wikimedia pictures.");
        clock.Now = clock.Now.AddMinutes(2);
        handler.Hang = false;
        handler.Malformed = true;
        Check((await archive.FindPicturesAsync(Item, default)).Failed, "Malformed JSON becomes a recoverable provider failure.");
        clock.Now = clock.Now.AddMinutes(2);
        handler.Malformed = false;
        Check((await archive.FindPicturesAsync(Item, default)).Images.Count == 1, "Malformed replies cannot poison future matches.");
    }

    public static async Task ResearchPipeline()
    {
        using var handler = new Handler();
        using var archive = Client(handler);
        var anchor = new GeoLocation(52.0834, 4.2911);
        var segment = new RouteStorySegment("area", 0, anchor, anchor, anchor, 0, 0, 0, 0, false, []);
        var query = new LocalRouteResearchQuery([segment], new ApproximateLiveLocation("The Hague", null, "Netherlands", null),
            [], ["history"], "en", [new("Laan van Meerdervoort", null, anchor)]);
        using var researchHandler = new ResearchHandler();
        using var http = new HttpClient(researchHandler);
        var researcher = new OpenAILocalRouteResearcher(http, new LocalRouteResearchOptions
            { Enabled = true, ApiKey = "openai-test-key", Model = "test-model" }, new Clock(), europeana: archive);
        var result = await researcher.ResearchAsync(query, default);
        Check(result.Stories.Count == 0, "Archive metadata alone must never become narration without independent citations.");
        Check(researchHandler.Input!.Contains(Item) && researchHandler.Input.Contains("archiveLeads")
            && researchHandler.Input.Contains("Independent", StringComparison.OrdinalIgnoreCase)
            && !researchHandler.Input.Contains("secret-echo") && !researchHandler.Input.Contains("test-key"),
            "Only sanitized leads and provenance rules reach research, never provider keys or raw bodies.");
        var calls = handler.Calls;
        await archive.FindResearchLeadsAsync(query with { Question = new("Who lived here?", StoryQuestionScope.Street,
            StoryQuestionFormat.Single, 1, 60) }, [], default);
        Check(handler.Calls == calls, "Explicit questions retain their existing research path.");
    }

    private static Dictionary<string, object> Record(string id = "view_1", string title = "Laan van Meerdervoort, The Hague",
        string rights = "http://creativecommons.org/licenses/by-sa/4.0/", string preview = Preview, bool noDistribute = false, string creator = "<a>Photographer</a>") => new()
    {
        ["id"] = "/123/" + id, ["type"] = "IMAGE", ["title"] = new[] { title },
        ["rights"] = new[] { rights }, ["edmPreview"] = new[] { preview }, ["previewNoDistribute"] = noDistribute,
        ["dcCreator"] = new[] { creator }, ["dataProvider"] = new[] { "City Archive" }, ["year"] = new[] { "1910" },
        ["dcDescription"] = new[] { "An archival street view of Laan van Meerdervoort in The Hague." },
        ["edmPlaceLabel"] = new[] { new { en = new[] { "The Hague" } } },
        ["edmPlaceLatitude"] = new[] { "48.85" }, ["edmPlaceLongitude"] = new[] { "2.35" }
    };
    private static void Check(bool valid, string message) { if (!valid) throw new Exception(message); }
    private sealed class Clock : TimeProvider
    {
        public DateTimeOffset Now = new(2026, 10, 9, 0, 0, 0, TimeSpan.Zero);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Factory(HttpMessageHandler handler) : IHttpClientFactory
    { public HttpClient CreateClient(string name) => new(handler, false); }
    private sealed class ResearchHandler : HttpMessageHandler
    {
        public string? Input;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            Input = body.RootElement.GetProperty("input").GetString();
            return new(HttpStatusCode.OK) { Content = new StringContent("""{"status":"completed","output":[]}""") };
        }
    }
    private sealed class Handler : HttpMessageHandler
    {
        public int Calls;
        public string? Key, Query;
        public bool Success = true;
        public bool Hang, Malformed;
        public HttpStatusCode Status = HttpStatusCode.OK;
        public Dictionary<string, object>[] Records = [Record()];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.Host != "api.europeana.eu")
            {
                var wiki = request.RequestUri.Host == "commons.wikimedia.org"
                    ? """{"query":{"pages":[{"imageinfo":[{"mime":"image/jpeg","thumburl":"https://upload.wikimedia.org/view.jpg","descriptionurl":"https://commons.wikimedia.org/wiki/File:View.jpg","extmetadata":{"Artist":{"value":"Photographer"},"LicenseShortName":{"value":"CC0"},"LicenseUrl":{"value":"https://creativecommons.org/publicdomain/zero/1.0/"}}}]}]}}"""
                    : """{"query":{"pages":[{"pageimage":"View.jpg"}]}}""";
                return new(HttpStatusCode.OK) { Content = new StringContent(wiki) };
            }
            Calls++;
            Key = request.Headers.GetValues("X-Api-Key").Single();
            Query = Uri.UnescapeDataString(request.RequestUri.Query);
            if (Hang) await Task.Delay(Timeout.Infinite, token);
            await Task.Delay(5, token);
            var result = new HttpResponseMessage(Status) { Content = new StringContent(Malformed ? "{broken"
                : JsonSerializer.Serialize(new { success = Success, apikey = "secret-echo", items = Records })) };
            result.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(120));
            return result;
        }
    }
}
