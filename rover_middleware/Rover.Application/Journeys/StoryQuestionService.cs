using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Microsoft.Extensions.Logging;
using Rover.Application.LiveContext;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Application.Journeys;

[JsonConverter(typeof(JsonStringEnumConverter))]
public enum StoryQuestionScope { Auto, Street, Neighbourhood, City, Route }
[JsonConverter(typeof(JsonStringEnumConverter))]
public enum StoryQuestionFormat { Auto, Single, ThenAndNow, Collection }

public sealed record StoryQuestionRequest(string Question, double Latitude, double Longitude)
{
    public StoryQuestionScope Scope { get; init; } = StoryQuestionScope.Auto;
    public StoryQuestionFormat Format { get; init; } = StoryQuestionFormat.Auto;
    public int? StoryCount { get; init; }
    public int AvailableNarrationSeconds { get; init; } = 300;
    public string Language { get; init; } = "en";
    public IReadOnlyList<GeoLocation>? RouteGeometry { get; init; }
}

public sealed record StoryResearchQuestion(string Text, StoryQuestionScope Scope,
    StoryQuestionFormat Format, int StoryCount, int AvailableNarrationSeconds);

public sealed record StoryQuestionResponse(string Status, StoryQuestionScope Scope,
    StoryQuestionFormat Format, int RequestedStories, int SearchRadiusMeters,
    IReadOnlyList<AdaptiveRouteStorySelection> Answers, string? Message);

// Explicit question research never changes the walk, arrival queue or autoplay collection.
public sealed class StoryQuestionService(ILocalRouteResearcher researcher, TimeProvider clock,
    ILogger<StoryQuestionService> logger)
{
    public async Task<StoryQuestionResponse> AskAsync(StoryQuestionRequest request, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (string.IsNullOrWhiteSpace(request.Question) || request.Question.Length > 1200
            || request.Question.Any(c => char.IsControl(c) && !char.IsWhiteSpace(c)))
            throw new ArgumentException("A question of 1 to 1200 characters is required.");
        if (!ValidLocation(new(request.Latitude, request.Longitude)))
            throw new ArgumentException("A valid current location is required.");
        if (!Enum.IsDefined(request.Scope) || !Enum.IsDefined(request.Format)
            || request.StoryCount is < 1 or > 5 || request.AvailableNarrationSeconds is < 30 or > 1800
            || request.Language is null || !Regex.IsMatch(request.Language, "^[a-z]{2}(-[A-Za-z]{2})?$"))
            throw new ArgumentException("Invalid scope, format, language, story count or narration budget.");
        var text = Regex.Replace(request.Question.Trim(), @"\s+", " ");
        var lower = text.ToLowerInvariant();
        var scope = request.Scope != StoryQuestionScope.Auto ? request.Scope
            : Regex.IsMatch(lower, @"\b(route|road ahead|walk ahead)\b") ? StoryQuestionScope.Route
            : Regex.IsMatch(lower, @"\b(city|town)\b") ? StoryQuestionScope.City
            : Regex.IsMatch(lower, @"\b(street|road)\b") ? StoryQuestionScope.Street
            : StoryQuestionScope.Neighbourhood;
        var format = request.Format != StoryQuestionFormat.Auto ? request.Format
            : Regex.IsMatch(lower, @"\b(then and now|then-and-now|100 years|changed over time|past with)\b")
                ? StoryQuestionFormat.ThenAndNow
            : Regex.IsMatch(lower, @"\b(three|five|[2-5]|turning points|collection)\b")
                ? StoryQuestionFormat.Collection : StoryQuestionFormat.Single;
        var count = format != StoryQuestionFormat.Collection ? 1
            : request.StoryCount ?? (Regex.IsMatch(lower, @"\b(five|5)\b") ? 5
                : Regex.IsMatch(lower, @"\b(four|4)\b") ? 4
                : Regex.IsMatch(lower, @"\b(two|2)\b") ? 2 : 3);
        if (format != StoryQuestionFormat.Collection && request.StoryCount is > 1)
            throw new ArgumentException("Multiple stories require Collection format.");
        var radius = scope switch { StoryQuestionScope.Street => 1000,
            StoryQuestionScope.City => 20000, StoryQuestionScope.Route => 1000, _ => 5000 };
        StoryQuestionResponse Response(string status, IReadOnlyList<AdaptiveRouteStorySelection> answers, string? message) =>
            new(status, scope, format, count, radius, answers, message);
        var center = new GeoLocation(request.Latitude, request.Longitude);
        IReadOnlyList<RouteStorySegment> segments;
        if (scope == StoryQuestionScope.Route)
        {
            if (request.RouteGeometry is not { Count: >= 2 and <= 120 } geometry
                || geometry.Any(p => p is null || !ValidLocation(p) || RouteMath.DistanceMeters(center, p) > 50000))
                return Response("needs_route", [], "Supply the route ahead, or ask about your current area instead.");
            segments = geometry.Zip(geometry.Skip(1), (start, end) => (start, end))
                .Select((pair, index) => new RouteStorySegment($"question-{index}", index,
                    pair.start, pair.end, pair.start, 0, 0, 0, 0, false, [])).ToArray();
        }
        else
        {
            segments = [new RouteStorySegment("question-area", 0, center, center, center, 0, 0, 0, 0, false, [])];
        }
        var query = new LocalRouteResearchQuery(segments, new ApproximateLiveLocation(null, null, null, null),
            [], [], request.Language)
        {
            AreaFirst = scope != StoryQuestionScope.Route, SearchRadiusMeters = radius, MaximumStories = count,
            Question = new(text, scope, format, count, request.AvailableNarrationSeconds)
        };
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(TimeSpan.FromSeconds(95));
        LocalRouteResearchResult result;
        try { result = await researcher.ResearchAsync(query, budget.Token).WaitAsync(budget.Token); }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error)
        {
            logger.LogWarning("Question research failed: {Kind}", error.GetType().Name);
            return Response("failed", [], "Research could not finish. Please try again.");
        }
        token.ThrowIfCancellationRequested();
        var answers = new List<AdaptiveRouteStorySelection>();
        var remaining = request.AvailableNarrationSeconds;
        foreach (var story in result.Stories.Where(s => Grounded(s, clock.GetUtcNow())
            && segments.Any(segment => RouteMath.DistanceToSegmentMeters(s.Anchor, segment.Start, segment.End) <= radius))
            .DistinctBy(s => s.StoryId))
        {
            // Whole variants only; never cut a spoken story off to meet the budget.
            var variant = story.Variants.Where(v => v.EstimatedDurationSeconds > 0
                    && v.EstimatedDurationSeconds <= remaining && v.Length != AdaptiveStoryLength.Deep)
                .OrderBy(v => Math.Abs((int)v.Length - (int)AdaptiveStoryLength.Standard)).FirstOrDefault();
            if (variant is null) continue;
            answers.Add(new(story, variant, "Explicitly requested, source-grounded answer."));
            remaining -= variant.EstimatedDurationSeconds;
            if (answers.Count == count) break;
        }
        return Response(answers.Count == count ? "ready" : answers.Count > 0 ? "partial" : result.Failed ? "failed" : "empty",
            answers, answers.Count == count ? null : answers.Count > 0
                ? "Only part of the requested collection fits the verified evidence and narration time."
                : result.Failed ? "Research could not finish. Please try again."
                : "There is not enough verified evidence to answer this question within the selected area and time.");
    }

    private static bool ValidLocation(GeoLocation point) => double.IsFinite(point.Latitude)
        && double.IsFinite(point.Longitude) && Math.Abs(point.Latitude) <= 90 && Math.Abs(point.Longitude) <= 180;

    private static bool Grounded(AdaptiveRouteStory story, DateTimeOffset now) =>
        ValidLocation(story.Anchor) && story.ExpiresUtc > now && story.Claims.Count > 0 && story.Sources.Count > 0
        && story.Claims.All(c => !string.IsNullOrWhiteSpace(c.Text) && c.SourceIds.Count > 0
            && c.SourceIds.All(id => story.Sources.Any(s => s.SourceId == id
                && Uri.TryCreate(s.Url, UriKind.Absolute, out var uri) && uri.Scheme is "https" or "http")))
        && story.Variants.All(v => !string.IsNullOrWhiteSpace(v.Narration) && v.ClaimIds.Count > 0
            && v.ClaimIds.All(id => story.Claims.Any(c => c.ClaimId == id)));
}
