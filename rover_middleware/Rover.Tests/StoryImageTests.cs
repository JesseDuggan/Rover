using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Logging.Abstractions;
using Rover.Infrastructure.Journeys;

internal static class StoryImageTests
{
    public static async Task SourcedImages()
    {
        using var handler = new Handler();
        using var service = new StoryImageService(new Factory(handler), NullLogger<StoryImageService>.Instance);
        var request = new StoryImageRequest(["https://en.wikipedia.org/wiki/Frankfurt"]);
        var result = await service.FindAsync(request, default);
        Check(result.Status == "ready" && result.Images.Count == 1, "Find article illustration.");
        Check(result.Images[0].Attribution == "Photographer" && result.Images[0].Caption == "Historic view",
            "Display plain-text credit and caption.");
        await service.FindAsync(request, default);
        Check(handler.Calls == 2, "Reuse cached metadata.");
        result = await service.FindAsync(new(["http://127.0.0.1/private", "https://en.wikipedia.org.evil.org/wiki/Test",
            "https://en.wikipedia.org:123/wiki/Test", "https://en.wikipedia.org/wiki/File:Test"]), default);
        Check(result.Images.Count == 0 && handler.Calls == 2, "Do not fetch arbitrary hosts or special pages.");
        handler.License = "https://example.org/all-rights-reserved";
        handler.File = "Restricted.jpg";
        result = await service.FindAsync(new(["https://de.wikipedia.org/wiki/Frankfurt"]), default);
        Check(result.Status == "empty", "Reject unsupported image rights.");
        handler.License = "https://creativecommons.org/licenses/by-sa/4.0/";
        handler.File = "View.jpg";
        result = await service.FindAsync(new(["https://www.wikidata.org/wiki/Q1792"]), default);
        Check(result.Images.Count == 1, "Resolve sourced Wikidata P18.");
        handler.Fail = true;
        result = await service.FindAsync(new(["https://fr.wikipedia.org/wiki/Francfort"]), default);
        Check(result.Status == "unavailable", "Provider failure must not become story failure.");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try { await service.FindAsync(request, cancelled.Token); throw new Exception("Cancellation lost."); }
        catch (OperationCanceledException) { }
    }
    public static async Task NearbyAndMetadata()
    {
        using var handler = new Handler { License = "http://creativecommons.org/licenses/by-sa/3.0/", IncludeThumbnail = false };
        using var service = new StoryImageService(new Factory(handler), NullLogger<StoryImageService>.Instance);
        var result = await service.FindAsync(new(["https://www.wikidata.org/entity/Q1792"]), default);
        Check(result.Images.Count == 1 && result.Images[0].LicenseUrl == "https://creativecommons.org/licenses/by-sa/3.0/",
            "Resolve discovery entity URLs, upgrade trusted legacy license links, and use original small images.");
        var calls = handler.Calls;
        result = await service.FindAsync(new(["https://commons.wikimedia.org/wiki/File:View.jpg"]), default);
        Check(result.Images.Count == 1 && handler.Calls == calls, "Direct Commons source reuses file metadata.");
        handler.NoPageImage = true;
        result = await service.FindAsync(new(["https://nl.wikipedia.org/wiki/Museum"]), default);
        Check(result.Images.Count == 1, "An article can use its exact Wikidata entity when its lead image is absent.");
        handler.NoPageImage = false;
        result = await service.FindAsync(new(["https://maps.google.com/place/test"], 52.0834, 4.2911), default);
        Check(result.Images.Count == 1 && result.Images[0].IsNearby && result.Images[0].Caption.StartsWith("Nearby museum:"),
            "Unsupported POI photo sources use explicitly labelled geotagged context, not a claimed POI match.");
        Check(handler.NearbyQuery?.Contains("ggsradius=500") == true && handler.NearbyQuery.Contains("ggslimit=5"),
            "Nearby image fallback stays bounded.");
        calls = handler.Calls;
        await service.FindAsync(new([], 52.0834, 4.2911), default);
        Check(handler.Calls == calls, "Stable stop coordinates reuse the nearby cache.");
        await service.FindAsync(new(["https://en.wikipedia.org/wiki/Known"], 53, 5), default);
        Check(handler.NearbyCalls == 1, "No extra nearby lookup when cited images are available.");
        foreach (var request in new[] { new StoryImageRequest([], 91, 0), new([], 0, 181), new([], 0), new([], double.NaN, 0) })
        {
            try { await service.FindAsync(request, default); throw new Exception("Invalid coordinates accepted."); }
            catch (ArgumentException) { }
        }
        handler.ErrorBody = true;
        result = await service.FindAsync(new(["https://en.wikipedia.org/wiki/Unavailable"]), default);
        Check(result.Status == "unavailable", "API errors inside HTTP 200 responses remain retryable, not cached as empty.");
        handler.ErrorBody = false;
        result = await service.FindAsync(new(["https://en.wikipedia.org/wiki/Unavailable"]), default);
        Check(result.Status == "ready", "Provider recovery is not hidden by an empty cache entry.");
    }
    private static void Check(bool valid, string message) { if (!valid) throw new Exception(message); }
    public static async Task LiveWikimedia()
    {
        using var service = new StoryImageService(new LiveFactory(), NullLogger<StoryImageService>.Instance);
        var result = await service.FindAsync(new(["https://en.wikipedia.org/wiki/Laan_van_Meerdervoort"]), default);
        Check(result.Status == "ready" && result.Images.Any(x => x.LicenseUrl.StartsWith("https://creativecommons.org/")),
            "Live Laan van Meerdervoort image must retain valid credits and license.");
        result = await service.FindAsync(new([], 52.0834, 4.2911), default);
        Check(result.Status == "ready" && result.Images.All(x => x.IsNearby), "Live geotagged context must be labelled nearby.");
    }
    private sealed class LiveFactory : IHttpClientFactory
    {
        public HttpClient CreateClient(string name)
        {
            var client = new HttpClient(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(10) };
            client.DefaultRequestHeaders.UserAgent.ParseAdd("WalkAbout/1.0 (https://github.com/JesseDuggan/Rover)");
            return client;
        }
    }
    private sealed class Factory(HttpMessageHandler handler) : IHttpClientFactory {
        public HttpClient CreateClient(string name) => new(handler, disposeHandler: false);
    }
    private sealed class Handler : HttpMessageHandler
    {
        public int Calls;
        public bool Fail;
        public bool ErrorBody;
        public bool IncludeThumbnail = true;
        public bool NoPageImage;
        public string File = "View.jpg";
        public string? NearbyQuery;
        public int NearbyCalls;
        public string License = "https://creativecommons.org/licenses/by-sa/4.0/";
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            token.ThrowIfCancellationRequested();
            if (Fail) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            var nearby = request.RequestUri!.Query.Contains("generator=geosearch");
            if (nearby) { NearbyQuery = request.RequestUri.Query; NearbyCalls++; }
            var json = ErrorBody ? """{"error":{"code":"maxlag"}}"""
                : request.RequestUri!.Host == "www.wikidata.org"
                ? """{"entities":{"Q1792":{"claims":{"P18":[{"mainsnak":{"datavalue":{"value":"View.jpg"}}}]}}}}"""
                : request.RequestUri.Host != "commons.wikimedia.org"
                ? JsonSerializer.Serialize(new { query = new { pages = new[] { new {
                    pageimage = NoPageImage ? null : File, title = "Nearby museum",
                    fullurl = "https://en.wikipedia.org/wiki/Nearby_museum", pageprops = new { wikibase_item = "Q1792" }
                } } } })
                : JsonSerializer.Serialize(new { query = new { pages = new[] { new { imageinfo = new[] { new {
                    mime = "image/jpeg", thumburl = IncludeThumbnail ? "https://upload.wikimedia.org/view.jpg" : null,
                    url = "https://upload.wikimedia.org/view.jpg",
                    width = 800, height = 600, size = 50000,
                    descriptionurl = "https://commons.wikimedia.org/wiki/File:" + File,
                    extmetadata = new { Artist = new { value = "<a>Photographer</a>" },
                        LicenseShortName = new { value = "CC BY-SA 4.0" }, LicenseUrl = new { value = License },
                        ImageDescription = new { value = "Historic view" } }
                } } } } } });
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json) });
        }
    }
}
