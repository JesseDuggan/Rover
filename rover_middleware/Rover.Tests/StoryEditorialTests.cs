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
        await Verify(false);
        await Verify(false, recovery: true);
        await Verify(false, recovery: true, areaRecovery: true);
        foreach (var scope in new[] { "neighbourhood", "city", "county", "region", "country" })
        {
            await Verify(false, scope: scope);
            await Verify(false, relevant: false, scope: scope);
        }
    }
    public static async Task QuestionEvidence()
    {
        await Verify(true);
        await Verify(true, false);
    }
    private static async Task Verify(bool question, bool relevant = true, bool recovery = false, string? scope = null, bool areaRecovery = false)
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
                if (calls % 2 == 1)
                {
                    var input = body.RootElement.GetProperty("input").GetString()!;
                    var instructions = body.RootElement.GetProperty("instructions").GetString()!;
                    Check(instructions.Contains("warm, conversational") && instructions.Contains("family-safe")
                        && instructions.Contains("political movements") && instructions.Contains("source disagreements"),
                        "Editorial instructions must reach route-free research.");
                    Check(!input.Contains("Frankfurt"), "Location research must not depend on an old city.");
                    if (!question)
                    {
                        Check(!input.Contains("All subjects must relate to the area within maximumStoryDistanceMeters")
                            && !input.Contains("Subjects must be within maximumStoryDistanceMeters"),
                            "Local-only instructions must not contradict geographic fallback.");
                        var reader = new Utf8JsonReader(Encoding.UTF8.GetBytes(input));
                        using var context = JsonDocument.ParseValue(ref reader);
                        Check(context.RootElement.GetProperty("routeAreas")[0].GetProperty("latitude").GetDouble()
                            == Math.Round(anchor.Latitude, 3), "Automatic research preserves neighbourhood-scale precision.");
                    }
                    if (calls == 3)
                        Check(input.Contains("Follow the geographic fallback policy in order"),
                            "Retry must research neighbourhood evidence without widening eligibility.");
                    if (question)
                        Check(input.Contains("workshop") && instructions.Contains("actual question")
                            && instructions.Contains("Superlatives") && instructions.Contains("copyrighted clips"),
                            "Question research needs its own topic and evidence safeguards.");
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
                    if (!question)
                        Check(body.RootElement.GetProperty("instructions").GetString()!.Contains("geographicScope local, neighbourhood, city, county, region or country"),
                            "Scope policy must reach classifier instructions, not just untrusted evidence.");
                    var cards = JsonSerializer.Serialize(new { stories = new[] { new {
                        evidenceIndex = 0, title = "Workshop records", kind = "history",
                        latitude = scope is not null ? anchor.Latitude + 0.03 : recovery && calls == 2 ? anchor.Latitude + 1 : anchor.Latitude, longitude = anchor.Longitude,
                        geographicScope = scope ?? "local",
                        geographicArea = scope is null ? null : "test archive",
                        geographicConnection = scope is null ? null : relevant
                            ? "The archive also documents the surrounding community." : "Unsupported connection to a different city.",
                        locationEvidence = "test archive", startsUtc = (string?)null, endsUtc = (string?)null,
                        audienceSuitability = audience, sensitivityNotice = (string?)null,
                        uncertainClaims = new[] { "Accounts disagree about its opening date.", "Invented dispute." },
                        answersQuestion = relevant
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
                new ApproximateLiveLocation(null, null, null, null), [], ["history"], "en") {
                    AreaFirst = !recovery || areaRecovery,
                    Question = question ? new("How did the workshop change?", StoryQuestionScope.Neighbourhood,
                        StoryQuestionFormat.ThenAndNow, 1, 180) : null
                }, default);
            if ((question || scope is not null) && !relevant)
            {
                Check(result.Stories.Count == 0, "Cited but irrelevant passages are not answers.");
                continue;
            }
            Check(result.Stories.Count == 1 && calls == (recovery ? 4 : 2), "Research uses at most one recovery attempt.");
            var story = result.Stories.Single();
            if (scope is not null)
            {
                Check(story.GeographicScope == scope && story.ContextOrigin == anchor,
                    "Broader context must retain its relevant origin and scope.");
                Check(story.Anchor.Latitude != anchor.Latitude,
                    "Never move a distant subject onto the route.");
                Check(story.Variants.All(v => v.Narration.StartsWith("For broader " + scope)),
                    "Every narration length must identify broader context.");
            }
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
