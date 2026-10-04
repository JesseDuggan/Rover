using Microsoft.Extensions.Logging.Abstractions;
using Rover.Application.Journeys;
using Rover.Domain.Walks;

internal static class StoryQuestionTests
{
    private static readonly GeoLocation Center = new(51.5, -0.12);
    public static async Task ScopeAndFormats()
    {
        var fake = new Researcher();
        var service = Service(fake);
        foreach (var (question, scope, format, count) in new[]
        {
            ("Tell me how this street got its name.", StoryQuestionScope.Street, StoryQuestionFormat.Single, 1),
            ("Tell me the story of this city through five turning points.", StoryQuestionScope.City, StoryQuestionFormat.Collection, 5),
            ("Tell me a then and now story about where I am.", StoryQuestionScope.Neighbourhood, StoryQuestionFormat.ThenAndNow, 1),
            ("Choose three places on my route that people overlook.", StoryQuestionScope.Route, StoryQuestionFormat.Collection, 3),
            ("Who was an overlooked local inventor?", StoryQuestionScope.Neighbourhood, StoryQuestionFormat.Single, 1),
            ("Present the different historical accounts of what happened here.", StoryQuestionScope.Neighbourhood, StoryQuestionFormat.Single, 1)
        })
        {
            var request = Request(question) with { RouteGeometry = [Center, new(51.501, -0.12)] };
            var response = await service.AskAsync(request, default);
            Check(response.Scope == scope && response.Format == format && response.RequestedStories == count,
                "Question scope and format must be resolved.");
            Check(fake.Query!.Question?.Text == question && fake.Query.MaximumStories == count
                && fake.Query.PublicPlaceNames.Count == 0 && fake.Query.Journey is null,
                "The actual question, not POI listings or an old walk, drives research.");
            Check(response.Status == "empty" && response.Message!.Contains("verified evidence"),
                "Missing evidence must not become filler.");
        }
        var calls = fake.Calls;
        Check((await service.AskAsync(Request("Tell me about the route ahead"), default)).Status == "needs_route"
            && fake.Calls == calls, "Do not invent a route.");
        await service.AskAsync(Request("Tell me about this city") with { Scope = StoryQuestionScope.Street }, default);
        Check(fake.Query!.Question!.Scope == StoryQuestionScope.Street, "Explicit scope wins.");
    }

    public static async Task EvidenceAndBudget()
    {
        var fake = new Researcher { Result = new([Story("one"), Story("two")], null) };
        var service = Service(fake);
        var request = Request("Tell me three stories");
        var response = await service.AskAsync(request, default);
        Check(response.Status == "partial" && response.Answers.Count == 2, "Partial coverage is explicit.");
        response = await service.AskAsync(request with { AvailableNarrationSeconds = 30 }, default);
        Check(response.Answers.Count == 1 && response.Answers[0].Variant.EstimatedDurationSeconds == 30,
            "Never truncate a story or exceed the narration budget.");
        foreach (var invalid in new[] {
            Story("bad") with { Sources = [] },
            Story("bad") with { ExpiresUtc = DateTimeOffset.UtcNow.AddMinutes(-1) },
            Story("bad") with { Anchor = new(40, 10) },
            Story("bad") with { Variants = [new(AdaptiveStoryLength.Standard, 30, "Unsupported", ["missing"])] }
        })
        {
            fake.Result = new([invalid], null);
            Check((await service.AskAsync(request, default)).Status == "empty", "Reject invalid evidence or geography.");
        }
        fake.Result = new([Story("sensitive") with { AudienceSuitability = "sensitive",
            SensitivityNotice = "This story discusses war." }], null);
        response = await service.AskAsync(Request("Tell me the local wartime history"), default);
        Check(response.Answers.Count == 1 && !response.Answers[0].Story.CanAutoplay
            && response.Answers[0].Story.SensitivityNotice is not null, "Explicit answers retain safety metadata.");
        fake.Result = new([], "upstream") { Failed = true };
        Check((await service.AskAsync(request, default)).Status == "failed", "Provider failure is not no evidence.");
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        try { await service.AskAsync(request, cancelled.Token); throw new Exception("Ignored cancellation"); }
        catch (OperationCanceledException) { }
    }

    public static async Task Validation()
    {
        var fake = new Researcher();
        var service = Service(fake);
        foreach (var request in new[] {
            Request(""), Request(new string('x', 1201)), Request("history") with { Latitude = double.NaN },
            Request("history") with { StoryCount = 6 }, Request("history") with { Scope = (StoryQuestionScope)99 },
            Request("history") with { AvailableNarrationSeconds = 0 }, Request("history") with { Language = "../../secret" },
            Request("history") with { Format = StoryQuestionFormat.Single, StoryCount = 3 }
        })
        {
            try { await service.AskAsync(request, default); throw new Exception("Invalid input accepted."); }
            catch (ArgumentException) { }
        }
        Check(fake.Calls == 0, "Reject invalid requests before spending research resources.");
    }

    private static StoryQuestionRequest Request(string question) => new(question, Center.Latitude, Center.Longitude);
    private static StoryQuestionService Service(Researcher fake) => new(fake, TimeProvider.System, NullLogger<StoryQuestionService>.Instance);
    private static AdaptiveRouteStory Story(string id) => new(id, "question-area", "", id,
        RouteStoryIntent.HiddenHistory, "history", Center, 0, 0,
        [new(AdaptiveStoryLength.Standard, 30, "An independently documented local history.", ["claim"])],
        [new("claim", "An independently documented local history.", ["archive"], .9)],
        [new("archive", "Archive", "History", "https://example.org/history", "Archive", DateTimeOffset.UtcNow, .9)],
        .9, DateTimeOffset.UtcNow.AddHours(1));
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class Researcher : ILocalRouteResearcher
    {
        public int Calls;
        public LocalRouteResearchQuery? Query;
        public LocalRouteResearchResult Result = new([], null);
        public Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken token)
        {
            Calls++; Query = query; return Task.FromResult(Result);
        }
    }
}
