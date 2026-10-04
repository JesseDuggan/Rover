using System.Net;
using System.Text;
using System.Text.Json;
using Rover.Application.Journeys;
using Rover.Application.LiveContext;
using Rover.Domain.Walks;
using Rover.Infrastructure.Journeys;

internal static class StoryEditorialTests
{
    public static async Task SafetyAndEvidence()
    {
        var anchor = new GeoLocation(52.2946778, 4.7108732);
        var segment = new RouteStorySegment("area", 0, anchor, anchor, anchor, 0, 0, 0, 0, false, []);
        const string passage = "This test archive describes a local workshop and the people who worked there. " +
            "Accounts disagree about its opening date. The collection preserves their tools and written records. " +
            "Those records explain how the workshop changed over time. The archive also documents the surrounding community.";
        foreach (var audience in new string?[] { "family", "sensitive", "mature", null })
        {
            var calls = 0;
            using var client = new HttpClient(new RoutingHttpMessageHandler(request =>
            {
                calls++;
                using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                string output;
                if (calls == 1)
                {
                    var input = body.RootElement.GetProperty("input").GetString()!;
                    Check(input.Contains("warm, conversational") && input.Contains("family-safe")
                        && input.Contains("political movements") && input.Contains("source disagreements"),
                        "Editorial instructions must reach route-free research.");
                    Check(!input.Contains("Frankfurt"), "Location research must not depend on an old city.");
                    output = JsonSerializer.Serialize(new { status = "completed", output = new[] { new { content = new[] { new {
                        text = passage + " [1]",
                        annotations = new[] { new { type = "url_citation", start_index = passage.Length + 1,
                            end_index = passage.Length + 4, url = "https://archive.example/history", title = "Test archive" } }
                    } } } } });
                }
                else
                {
                    Check(body.RootElement.GetProperty("instructions").GetString()!.Contains("audienceSuitability"),
                        "Classifier must perform an audience review.");
                    var cards = JsonSerializer.Serialize(new { stories = new[] { new {
                        evidenceIndex = 0, title = "Workshop records", kind = "history",
                        latitude = anchor.Latitude, longitude = anchor.Longitude,
                        locationEvidence = "test archive", startsUtc = (string?)null, endsUtc = (string?)null,
                        audienceSuitability = audience, sensitivityNotice = (string?)null,
                        uncertainClaims = new[] { "Accounts disagree about its opening date.", "Invented dispute." }
                    } } });
                    output = JsonSerializer.Serialize(new { status = "completed", output = new[] { new { content = new[] { new { text = cards } } } } });
                }
                return new HttpResponseMessage(HttpStatusCode.OK) {
                    Content = new StringContent(output, Encoding.UTF8, "application/json")
                };
            }));
            var researcher = new OpenAILocalRouteResearcher(client,
                new() { Enabled = true, ApiKey = "test", Model = "test" }, TimeProvider.System);
            var result = await researcher.ResearchAsync(new([segment],
                new ApproximateLiveLocation(null, null, null, null), [], ["history"], "en") { AreaFirst = true }, default);
            Check(result.Stories.Count == 1 && calls == 2, "Research remains bounded to two calls.");
            var story = result.Stories.Single();
            Check(story.CanAutoplay == (audience == "family"), "Only reviewed family material may autoplay.");
            Check(story.UncertainClaims.SequenceEqual(new[] { "Accounts disagree about its opening date." }),
                "Uncertainty must be grounded in the passage.");
            Check(story.Variants.Count == 4, "All four listening lengths must exist.");
            Check(story.Variants.All(v => v.Narration.Contains("Accounts disagree")),
                "Short versions must not drop a disputed claim's qualification.");
            Check(story.Claims.All(c => c.SourceIds.Count > 0), "Every claim retains its citations.");
            if (audience is "sensitive" or "mature")
                Check(!string.IsNullOrWhiteSpace(story.SensitivityNotice), "Sensitive content needs a notice.");
        }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
