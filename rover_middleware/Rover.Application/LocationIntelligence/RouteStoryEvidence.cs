using System.Text.RegularExpressions;

namespace Rover.Application.LocationIntelligence;

public static class RouteStoryEvidence
{
    public static int Priority(LocationFact fact)
    {
        if (!fact.IsSuitableForNarration || fact.ConfidenceScore < 0.65 || string.IsNullOrWhiteSpace(fact.FactText)) return 0;
        var type = fact.FactType.ToLowerInvariant();
        if (type == "encyclopedic_summary") return 3;
        if (type.Contains("history") || type.Contains("historical") || type.Contains("architecture")
            || type.Contains("culture") || type.Contains("origin") || type.Contains("geology")) return 2;
        return 0;
    }

    public static IEnumerable<LocationFact> SpokenClaims(LocationFact fact)
    {
        if (fact.FactType != "encyclopedic_summary") { yield return fact; yield break; }
        var sentences = Regex.Split(fact.FactText.Trim(), @"(?<=[.!?])\s+");
        var passage = "";
        var index = 0;
        foreach (var sentence in sentences)
        {
            passage = passage.Length == 0 ? sentence : passage + " " + sentence;
            // Keep short fragments such as abbreviated names with the following sentence.
            if (passage.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length < 8) continue;
            yield return fact with { FactId = $"{fact.FactId}:passage-{index++}", FactText = passage };
            passage = "";
        }
        if (passage.Length > 0)
            yield return fact with { FactId = $"{fact.FactId}:passage-{index}", FactText = passage };
    }
}
