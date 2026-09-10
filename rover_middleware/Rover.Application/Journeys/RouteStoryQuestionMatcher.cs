using System.Text.RegularExpressions;

namespace Rover.Application.Journeys;

public static class RouteStoryQuestionMatcher
{
    private static readonly HashSet<string> Filler = new(StringComparer.OrdinalIgnoreCase)
    {
        "a", "an", "the", "this", "that", "these", "those", "here", "there", "area", "nearby",
        "what", "who", "when", "where", "why", "how", "is", "are", "was", "were", "does", "do", "did",
        "tell", "me", "about", "please", "can", "could", "you", "i", "we", "us", "our", "of", "in",
        "on", "at", "to", "for", "and", "with", "happens", "happened", "happening", "more", "detail",
        "details", "quick", "brief", "deep"
    };

    public static int Score(AdaptiveRouteStory story, StoryIntentClassification question)
    {
        var terms = Tokens(question.SanitizedQuestion).Where(term => !Filler.Contains(term)).Distinct().ToArray();
        if (terms.Length == 0)
            return question.Intent == RouteStoryIntent.GeneralLocationQuestion || story.Intent == question.Intent ? 1 : 0;

        var title = Tokens(story.Title).ToHashSet();
        var evidence = Tokens(string.Join(" ", story.Claims.Select(claim => claim.Text).Prepend(story.Title))).ToHashSet();
        // A specific question must be supported, not replaced by the closest POI.
        if (terms.Any(term => !evidence.Contains(term))) return 0;
        return terms.Sum(term => title.Contains(term) ? 5 : 2)
            + (story.Intent == question.Intent ? 1 : 0);
    }

    private static IEnumerable<string> Tokens(string value) =>
        Regex.Matches(value.ToLowerInvariant(), @"[\p{L}\p{N}]+")
            .Select(match => match.Value);
}
