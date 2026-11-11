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
        SpokenEditChecks();
        await Verify(false);
        await Verify(false, crossSentenceQualifier: true);
        await Verify(false, briefEvidence: true);
        await Verify(false, edited: true);
        await EmptyClassificationRecovery(false);
        await EmptyClassificationRecovery(true);
        await MissingCitationsRemainRejected();
        await Verify(true, mismatchedVenue: true);
        await Verify(false, recovery: true);
        await Verify(false, foodOnly: true);
        await Verify(true, foodOnly: true);
        await Verify(false, recovery: true, areaRecovery: true);
        foreach (var coordinateCase in new[] { "missing", "null", "zero" })
            await Verify(false, recovery: true, areaRecovery: true, coordinateCase: coordinateCase);
        foreach (var scope in new[] { "neighbourhood", "city", "county", "region", "country" })
        {
            await Verify(false, scope: scope);
            await Verify(false, relevant: false, scope: scope);
        }
    }
    public static async Task QuestionEvidence()
    {
        await Verify(true);
        await Verify(true, gap: true);
        await Verify(true, false);
        await Verify(true, rejectedDraft: "What I searched and why it fell short: I searched the archive.");
        await Verify(true, rejectedDraft: "This plaque marks the exact spot of the historic photograph.");
    }
    private static async Task MissingCitationsRemainRejected()
    {
        var calls = 0;
        using var client = new HttpClient(new RoutingHttpMessageHandler(request =>
        {
            calls++;
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(
                """{"status":"completed","output":[{"content":[{"text":"An uncited answer about a local workshop is not sufficient evidence for narration.","annotations":[]}]}]}""") };
        }));
        var anchor = new GeoLocation(44.9, -76.25);
        var segment = new RouteStorySegment("area", 0, anchor, anchor, anchor, 0, 0, 0, 0, false, []);
        var researcher = new OpenAILocalRouteResearcher(client, new() { Enabled = true, ApiKey = "test", Model = "test" }, TimeProvider.System);
        var result = await researcher.ResearchAsync(new([segment], new ApproximateLiveLocation(null, null, null, null), [], ["history"], "en") { AreaFirst = true }, default);
        Check(calls == 2 && result.Failed && result.Stories.Count == 0,
            "Missing citations get only one bounded retry and never become narration.");
    }

    private static async Task EmptyClassificationRecovery(bool remainsEmpty)
    {
        var anchor = new GeoLocation(44.9, -76.25);
        var calls = 0;
        var events = new List<StoryInspectionEvent>();
        var previous = StoryInspection.Listener.Value;
        StoryInspection.Listener.Value = events.Add;
        try
        {
            using var client = new HttpClient(new RoutingHttpMessageHandler(request =>
            {
                using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                calls++;
                string output;
                if (calls % 2 == 1)
                {
                    var text = "The Riverside workshop made tools for local farms. Its surviving workbench explains how workers shaped each handle by hand. Location: Riverside workshop; latitude 44.9; longitude -76.25.";
                    output = JsonSerializer.Serialize(new { status = "completed", output = new[] { new { content = new[] { new {
                        text = text + " [1]", annotations = new[] { new { type = "url_citation", start_index = text.Length + 1,
                            end_index = text.Length + 4, url = "https://archive.example/workshop", title = "Workshop archive" } }
                    } } } } });
                }
                else
                {
                    var instructions = body.RootElement.GetProperty("instructions").GetString()!;
                    Check(instructions.Contains("EVERY evidenceIndex") && instructions.Contains("retain the otherwise usable card"),
                        "Classification accounts for passages and preserves unresolved geographic evidence for validation.");
                    var text = calls == 2 || remainsEmpty
                        ? "{\"stories\":[],\"omitted\":[{\"evidenceIndex\":0,\"reason\":\"insufficient_evidence\"}]}"
                        : JsonSerializer.Serialize(new { stories = new[] { new {
                            evidenceIndex = 0, title = "Workshop tools", kind = "history", latitude = 44.9, longitude = -76.25,
                            locationEvidence = "Riverside workshop", audienceSuitability = "family", geographicScope = "local"
                        } }, omitted = Array.Empty<object>() });
                    output = JsonSerializer.Serialize(new { status = "completed", output = new[] { new { content = new[] { new { text } } } } });
                }
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(output) };
            }));
            var researcher = new OpenAILocalRouteResearcher(client, new LocalRouteResearchOptions { Enabled = true, ApiKey = "test", Model = "test" }, TimeProvider.System);
            var segment = new RouteStorySegment("area", 0, anchor, anchor, anchor, 0, 0, 0, 0, false, []);
            var result = await researcher.ResearchAsync(new([segment], new ApproximateLiveLocation(null, null, null, null), [], ["history"], "en") { AreaFirst = true, MaximumStories = 2 }, default);
            Check(calls == 4, "Empty classification has exactly one bounded research recovery.");
            Check(result.Stories.Count == (remainsEmpty ? 0 : 1), "Recovery never invents a card for still-empty evidence.");
            Check(events.Any(e => e.Stage == "Evidence classification" && e.Reason.Contains("insufficient_evidence")),
                "Omitted evidence is visible in inspector.");
            Check(events.Count(e => e.Stage == "Evidence recovery") == 1, "Recovery is recorded once.");
        }
        finally { StoryInspection.Listener.Value = previous; }
    }

    private static async Task Verify(bool question, bool relevant = true, bool recovery = false, bool foodOnly = false, string? scope = null, bool areaRecovery = false, string? coordinateCase = null, string? rejectedDraft = null, bool gap = false, bool mismatchedVenue = false, bool crossSentenceQualifier = false, bool briefEvidence = false, bool edited = false)
    {
        var anchor = new GeoLocation(52.2946778, 4.7108732);
        var segment = new RouteStorySegment("area", 0, anchor, anchor, anchor, 0, 0, 0, 0, false, []);
        var passage = (rejectedDraft ?? "") + " This test archive describes a local workshop and the people who worked there. " +
            "Accounts disagree about its opening date. The workshop at 12 King Street preserves their tools and written records. " +
            "Those records explain how the workshop changed over time. The archive also documents the surrounding community. " +
            "Apprentices learned to repair the tools here. The upper room stored finished work. " +
            "Location: test archive; latitude 52.295; longitude 4.711.";
        if (briefEvidence) passage = passage.Replace("Apprentices learned to repair the tools here. The upper room stored finished work. ", "");
        if (mismatchedVenue) passage = passage.Replace("test archive", "North Perth Town Hall");
        foreach (var audience in new string?[] { "family", "sensitive", "mature", null })
        {
            var calls = 0;
            using var client = new HttpClient(new RoutingHttpMessageHandler(request =>
            {

                using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                if (body.RootElement.GetProperty("instructions").GetString()!.Contains("local reference librarian"))
                    return new HttpResponseMessage(HttpStatusCode.OK) {
                        Content = new StringContent("""{"status":"completed","output":[{"content":[{"annotations":[{"type":"url_citation","url":"https://archive.example/record-16"},{"type":"url_citation","url":"http://localhost/private"}]}]}]}""")
                    };
                calls++;
                string output;
                if (calls % 2 == 1)
                {
                    Check(body.RootElement.GetProperty("instructions").GetString()!.Contains(NarrationAddressPolicy.Instructions),
                        "Every research path receives the shared narration address rule.");
                    Check(body.RootElement.GetProperty("instructions").GetString()!.Contains(SpokenStoryQuality.Instructions),
                        "Questions, gaps and automatic research receive the shared spoken-quality guidance.");
                    var input = body.RootElement.GetProperty("input").GetString()!;
                    var instructions = body.RootElement.GetProperty("instructions").GetString()!;
                    Check(instructions.Contains("warm, conversational") && instructions.Contains("family-safe")
                        && instructions.Contains("political movements") && instructions.Contains("source disagreements"),
                        "Editorial instructions must reach route-free research.");
                    Check(!input.Contains("Frankfurt"), "Location research must not depend on an old city.");
                    if (gap) Check(input.Contains("https://archive.example/record-16") && !input.Contains("localhost"),
                        "Gap research should receive the cited public record and discard invalid links.");
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
                    var input = body.RootElement.GetProperty("input").GetString()!;
                    var reader = new Utf8JsonReader(Encoding.UTF8.GetBytes(input));
                    using var payload = JsonDocument.ParseValue(ref reader);
                    Check(payload.RootElement.GetProperty("route").ValueKind == JsonValueKind.Object,
                        "Classification context must be an object, not double-encoded JSON.");
                    Check(body.RootElement.GetProperty("instructions").GetString()!.Contains("audienceSuitability"),
                        "Classifier must perform an audience review.");
                    Check(body.RootElement.GetProperty("instructions").GetString()!.Contains("independently of factual confidence")
                        && body.RootElement.GetProperty("instructions").GetString()!.Contains("deadly disaster remain sensitive"),
                        "Benign disputes and distressing subject matter must be classified separately.");
                    if (!question)
                        Check(body.RootElement.GetProperty("instructions").GetString()!.Contains("geographicScope local, neighbourhood, city, county, region or country"),
                            "Scope policy must reach classifier instructions, not just untrusted evidence.");
                    var cards = JsonSerializer.Serialize(new { stories = new[] { new {
                        evidenceIndex = 0, title = "Workshop records", kind = "history",
                        latitude = mismatchedVenue ? anchor.Latitude + 1 : scope is not null ? anchor.Latitude + 0.03 : recovery && calls == 2 ? anchor.Latitude + 1 : anchor.Latitude, longitude = anchor.Longitude,
                        geographicScope = scope ?? "local",
                        geographicArea = scope is null ? null : "test archive",
                        geographicConnection = scope is null ? null : relevant
                            ? "The archive also documents the surrounding community." : "Unsupported connection to a different city.",
                        locationEvidence = mismatchedVenue ? "North Perth Town Hall" : "test archive", startsUtc = (string?)null, endsUtc = (string?)null,
                        audienceSuitability = audience, sensitivityNotice = (string?)null,
                        uncertainClaims = new[] { crossSentenceQualifier ? "worked there. Accounts disagree" : "Accounts disagree about its opening date.", "Invented dispute." },
                        spokenSentences = edited ? System.Text.RegularExpressions.Regex.Split(passage.Trim(), @"(?<=[.!?])\s+")
                            .Where(t => !t.StartsWith("Location:")).Select(t => new SpokenStorySentence(t, [t])).ToArray() : null,
                        answersQuestion = relevant
                    } } });
                    if (coordinateCase is not null && calls == 2)
                    {
                        var parsed = System.Text.Json.Nodes.JsonNode.Parse(cards)!;
                        var card = parsed["stories"]![0]!.AsObject();
                        foreach (var key in new[] { "latitude", "longitude" })
                        {
                            if (coordinateCase == "missing") card.Remove(key);
                            else card[key] = coordinateCase == "zero" ? System.Text.Json.Nodes.JsonValue.Create(0) : null;
                        }
                        cards = parsed.ToJsonString();
                    }
                    output = JsonSerializer.Serialize(new { status = "completed", output = new[] { new { content = new[] { new { text = cards } } } } });
                }
                return new HttpResponseMessage(HttpStatusCode.OK) {
                    Content = new StringContent(output, Encoding.UTF8, "application/json")
                };
            }));
            var researcher = new OpenAILocalRouteResearcher(client,
                new() { Enabled = true, ApiKey = "test", Model = "test" }, TimeProvider.System);
            var result = await researcher.ResearchAsync(new([segment],
                new ApproximateLiveLocation(null, null, null, null), [], foodOnly ? ["food"] : ["history"], "en") {
                    PublicPlaces = mismatchedVenue ? [new("Town Hall - Perth", null, anchor)] : null,
                    AreaFirst = !recovery || areaRecovery,
                    Question = question ? new(gap ? "Research this block or landscape and its workshop." : "How did the workshop change?", StoryQuestionScope.Neighbourhood,
                        StoryQuestionFormat.ThenAndNow, 1, 180) : null
                }, default);
            if (mismatchedVenue)
            {
                Check(result.Stories.Count == 0, "A longer name must not inherit a selected place pin and bypass geographic rejection.");
                continue;
            }
            if (rejectedDraft is not null)
            {
                Check(result.Stories.Count == 0, "An annotated failed search or overprecise draft must not reach playback.");
                continue;
            }
            if (foodOnly && !question)
            {
                Check(result.Stories.Count == 0, "Automatic history must not override food-only preferences.");
                continue;
            }
            if ((question || scope is not null) && !relevant)
            {
                Check(result.Stories.Count == 0, "Cited but irrelevant passages are not answers.");
                continue;
            }
            Check(result.Stories.Count == 1 && calls == (recovery ? 4 : 2), "Research uses at most one recovery attempt.");
            var story = result.Stories.Single();
            if (edited) Check(story.Claims.All(c => c.ClaimId.Contains(":spoken:")), "Valid spoken edits reach all research paths with source references intact.");
            Check(story.Claims.Any(c => c.Text.Contains("12 King Street")), "Original address evidence must remain intact.");
            Check(story.Variants.All(v => !v.Narration.Contains("12 King Street")), "All spoken variants omit address numbers.");
            Check(story.Variants.All(v => !v.Narration.Contains("Location:") && !v.Narration.Contains("latitude")),
                "Coordinate metadata must never become spoken narration.");
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
            Check(story.UncertainClaims.SequenceEqual(new[] { crossSentenceQualifier ? "worked there. Accounts disagree" : "Accounts disagree about its opening date." }),
                "Uncertainty must be grounded in the passage.");
            Check(story.Variants.Count == 4, "All four listening lengths must exist.");
            Check(story.Variants.Select(v => v.Narration.Length).Zip(story.Variants.Skip(1).Select(v => v.Narration.Length),
                (shorter, longer) => shorter < longer).All(increasing => increasing),
                "Qualified stories with enough evidence must grow from Quick through Deep.");
            Check(story.Variants.All(v => v.Narration.Contains("Accounts disagree")),
                "Short versions must not drop a disputed claim's qualification.");
            Check(story.Claims.All(c => c.SourceIds.Count > 0), "Every claim retains its citations.");
            if (audience is "sensitive" or "mature")
                Check(!string.IsNullOrWhiteSpace(story.SensitivityNotice), "Sensitive content needs a notice.");
        }
    }

    private static void SpokenEditChecks()
    {
        var evidence = "The workshop opened in 1820. Accounts disagree about its opening date. Workers repaired farm tools. Apprentices trained in the upper room. The surviving bench has tool marks.";
        SpokenStorySentence[] sentences = [
            new("The workshop opened in 1820. Accounts disagree about its opening date.", ["The workshop opened in 1820. Accounts disagree about its opening date."]),
            new("Workers repaired farm tools.", ["Workers repaired farm tools."]),
            new("Apprentices trained in the upper room.", ["Apprentices trained in the upper room."]),
            new("The surviving bench has tool marks.", ["The surviving bench has tool marks."])
        ];
        string[] caveats = ["Accounts disagree about its opening date."];
        Check(SpokenStoryDraft.TryPrepare(evidence, sentences, caveats, out var draft)
            && draft.Contains(caveats[0]), "A supported spoken edit retains its caveat.");
        var missingCaveat = sentences.ToArray(); missingCaveat[0] = sentences[0] with { Text = "The workshop opened in 1820." };
        Check(!SpokenStoryDraft.TryPrepare(evidence, missingCaveat, caveats, out _), "An edit cannot drop a historical qualification.");
        var inventedQuote = sentences.ToArray(); inventedQuote[1] = sentences[1] with { EvidenceQuotes = ["An invented archive description."] };
        Check(!SpokenStoryDraft.TryPrepare(evidence, inventedQuote, caveats, out _), "Supporting excerpts must exist in the cited passage.");
        var inventedYear = sentences.ToArray(); inventedYear[0] = sentences[0] with { Text = sentences[0].Text.Replace("1820", "1850") };
        Check(!SpokenStoryDraft.TryPrepare(evidence, inventedYear, caveats, out _), "Spoken edits cannot invent a year.");
        foreach (var unsupported in new[] { "1990s", "21st", "50km" })
        {
            var changed = sentences.ToArray(); changed[0] = sentences[0] with { Text = sentences[0].Text.Replace("1820", unsupported) };
            Check(!SpokenStoryDraft.TryPrepare(evidence, changed, caveats, out _), "Unsupported decades, ordinals and attached units fail numeric validation.");
        }
        Check(!SpokenStoryDraft.TryPrepare(evidence, sentences, [], out _, isLegend: true),
            "Legends with unidentified attribution retain original evidence, not an edited version.");
        var overloaded = sentences.ToArray(); overloaded[1] = sentences[1] with { Text = string.Join(" ", Enumerable.Repeat("word", 40)) };
        Check(!SpokenStoryDraft.TryPrepare(evidence, overloaded, caveats, out _), "Overloaded edited sentences are rejected.");
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
