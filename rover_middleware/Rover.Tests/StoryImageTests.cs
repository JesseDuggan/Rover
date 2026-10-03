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
        result = await service.FindAsync(new(["https://de.wikipedia.org/wiki/Frankfurt"]), default);
        Check(result.Status == "empty", "Reject unsupported image rights.");
        handler.License = "https://creativecommons.org/licenses/by-sa/4.0/";
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
    private static void Check(bool valid, string message) { if (!valid) throw new Exception(message); }
    private sealed class Factory(HttpMessageHandler handler) : IHttpClientFactory {
        public HttpClient CreateClient(string name) => new(handler, disposeHandler: false);
    }
    private sealed class Handler : HttpMessageHandler
    {
        public int Calls;
        public bool Fail;
        public string License = "https://creativecommons.org/licenses/by-sa/4.0/";
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            token.ThrowIfCancellationRequested();
            if (Fail) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            var json = request.RequestUri!.Host == "www.wikidata.org"
                ? """{"entities":{"Q1792":{"claims":{"P18":[{"mainsnak":{"datavalue":{"value":"View.jpg"}}}]}}}}"""
                : request.RequestUri.Host != "commons.wikimedia.org"
                ? """{"query":{"pages":[{"pageimage":"View.jpg"}]}}"""
                : JsonSerializer.Serialize(new { query = new { pages = new[] { new { imageinfo = new[] { new {
                    mime = "image/jpeg", thumburl = "https://upload.wikimedia.org/view.jpg",
                    descriptionurl = "https://commons.wikimedia.org/wiki/File:View.jpg",
                    extmetadata = new { Artist = new { value = "<a>Photographer</a>" },
                        LicenseShortName = new { value = "CC BY-SA 4.0" }, LicenseUrl = new { value = License },
                        ImageDescription = new { value = "Historic view" } }
                } } } } } });
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(json) });
        }
    }
}
