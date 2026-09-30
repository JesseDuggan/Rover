using System.Net;
using System.Text;
using System.Text.Json;
using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;
using Rover.Infrastructure.LocationIntelligence;

internal static class PhotoIdentificationTests
{
    private const string Png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jD1sAAAAASUVORK5CYII=";
    private static readonly PhotoIdentificationRequest Input = new(Png, 48.137123, 11.575456);
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static PhotoIdentificationService Service(Handler handler, Resolver resolver, bool enabled = true) => new(
        new HttpClient(handler), new() { Enabled = enabled, ApiKey = "test-key", Model = "test-vision" }, resolver);

    public static Task Validation()
    {
        PhotoIdentificationService.Validate(Input);
        foreach (var input in new[] { Input with { ImageBase64 = "invalid" }, Input with { ImageBase64 = new string('A', 2_800_001) },
            Input with { Latitude = double.NaN }, Input with { Longitude = 181 }, Input with { ImageBase64 = Convert.ToBase64String(new byte[100]) } })
        {
            try { PhotoIdentificationService.Validate(input); throw new InvalidOperationException("Bad image accepted."); }
            catch (ArgumentException) { }
        }
        return Task.CompletedTask;
    }

    public static async Task ConfirmationAndPrivacy()
    {
        var handler = new Handler();
        var resolver = new Resolver();
        var result = await Service(handler, resolver).IdentifyAsync(Input, default);
        Check(result.Status == CandidateObservationResolutionStatus.Ambiguous && result.SelectedPlaceId is null, "Visual identity must require confirmation.");
        Check(result.Candidates.Count == 1 && result.Candidates[0].Place.Name == "Test monument", "Only nearby sourced candidates survive.");
        Check(resolver.Query?.RecognizedText == "Test monument", "Resolve the name against sourced places.");
        using var body = JsonDocument.Parse(handler.Body!);
        Check(!body.RootElement.GetProperty("store").GetBoolean(), "Do not store responses.");
        Check(!handler.Body!.Contains("48.137123") && !handler.Body.Contains("11.575456"), "Do not send precise GPS to vision.");
        Check(body.RootElement.GetProperty("input")[0].GetProperty("content")[1].GetProperty("image_url").GetString() == "data:image/png;base64," + Png, "Image sent as bounded data URL.");
    }

    public static async Task Failures()
    {
        foreach (var handler in new[] { new Handler { Status = HttpStatusCode.Unauthorized }, new Handler { Name = "" },
            new Handler { Malformed = true }, new Handler { Incomplete = true } })
        {
            var resolver = new Resolver();
            var result = await Service(handler, resolver).IdentifyAsync(Input, default);
            Check(result.Candidates.Count == 0 && resolver.Query is null, "Failure must not fabricate a candidate.");
        }
        var disabledHandler = new Handler();
        await Service(disabledHandler, new Resolver(), false).IdentifyAsync(Input, default);
        Check(disabledHandler.Body is null, "Disabled feature must not send images.");
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        try { await Service(new Handler(), new Resolver()).IdentifyAsync(Input, cancellation.Token); throw new InvalidOperationException("Cancellation swallowed."); }
        catch (OperationCanceledException) { }
    }

    private sealed class Handler : HttpMessageHandler
    {
        public HttpStatusCode Status { get; init; } = HttpStatusCode.OK;
        public string Name { get; init; } = "Test monument";
        public bool Malformed { get; init; }
        public bool Incomplete { get; init; }
        public string? Body { get; private set; }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Body = await request.Content!.ReadAsStringAsync(cancellationToken);
            var json = JsonSerializer.Serialize(new { status = Incomplete ? "incomplete" : "completed", output = new[] {
                new { type = "message", content = new[] { new { type = "output_text", text = JsonSerializer.Serialize(new { searchName = Name }) } } } } });
            return new(Status) { Content = new StringContent(Malformed ? "not json" : json, Encoding.UTF8, "application/json") };
        }
    }

    private sealed class Resolver : ICandidateObservationResolutionService
    {
        public CandidateObservationQuery? Query { get; private set; }
        public Task<CandidateObservationResolution> ResolveAsync(CandidateObservationQuery query, CancellationToken cancellationToken)
        {
            Query = query;
            var source = new LocationSource("Test", "1", "https://example.org/monument", "Test", null, DateTimeOffset.UtcNow, 1);
            var place = new LocationPlace("test:1", "Test monument", new GeoLocation(Input.Latitude, Input.Longitude), null,
                [], null, [], [source], new Dictionary<string, string>(), 0, null, null, null, 1, 1, [], [], null, null, DateTimeOffset.UtcNow);
            CandidateObservationMatch Match(LocationPlace p) => new(p, 1, 1, 1, 1, []);
            return Task.FromResult(new CandidateObservationResolution(CandidateObservationResolutionStatus.Verified, "test:1",
                [Match(place), Match(place with { CanonicalId = "far", Coordinates = new GeoLocation(0, 0) }),
                    Match(place with { CanonicalId = "unsourced", SourceReferences = [] })], "verified", []));
        }
    }
}
