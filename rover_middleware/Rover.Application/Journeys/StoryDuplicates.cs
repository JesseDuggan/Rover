using System.Text.RegularExpressions;
using Rover.Application.Walks;

namespace Rover.Application.Journeys;

public static class StoryDuplicates
{
    public static IReadOnlyList<AdaptiveRouteStory> Remove(IEnumerable<AdaptiveRouteStory> stories)
    {
        var kept = new List<AdaptiveRouteStory>();
        foreach (var story in stories)
        {
            if (kept.Any(previous =>
                string.Equals(previous.StoryId, story.StoryId, StringComparison.OrdinalIgnoreCase) ||
                (RouteMath.DistanceMeters(previous.Anchor, story.Anchor) <= 250 && SimilarTitle(previous.Title, story.Title))))
                continue;
            kept.Add(story);
        }
        return kept;
    }

    public static bool SimilarTitle(string first, string second)
    {
        var a = Words(first);
        var b = Words(second);
        if (a.Count == 0 || b.Count == 0) return false;
        if (a.SetEquals(b)) return true;
        var overlap = a.Intersect(b).Count();
        // Require substantial shared wording; sharing only a place name is not enough.
        return overlap >= 3 && overlap / (double)Math.Min(a.Count, b.Count) >= 0.9 &&
            overlap / (double)Math.Max(a.Count, b.Count) >= 0.65;
    }

    private static HashSet<string> Words(string title) => Regex.Matches(title.ToLowerInvariant(), @"[\p{L}\p{N}]+")
        .Select(match => match.Value)
        .Where(word => word is not ("a" or "an" or "the" or "as" or "of" or "in" or "and" or "at" or "to"))
        .ToHashSet(StringComparer.Ordinal);
}
