namespace Rover.Infrastructure.Journeys;

public static class StoryInterestPolicy
{
    private static readonly Dictionary<string, string[]> Categories = new(StringComparer.OrdinalIgnoreCase)
    {
        ["history"] = ["history", "then_and_now", "legend", "social_change", "place_names"],
        ["architecture"] = ["architecture", "look_closer"],
        ["culture"] = ["culture", "local_life", "pop_culture"],
        ["art"] = ["culture", "look_closer"], ["movies"] = ["pop_culture"],
        ["hidden gems"] = ["hidden_gem"],
        ["food"] = ["food"], ["food and drink"] = ["food"],
        ["nature"] = ["nature"], ["notable people"] = ["people"],
        ["film and television"] = ["pop_culture"], ["unusual facts"] = ["fun_fact", "hidden_gem"],
        ["events"] = ["event", "news"], ["current events"] = ["event", "news"],
        ["local events"] = ["event", "news"], ["sports"] = ["sports"], ["weather"] = ["weather"]
    };

    public static bool Allows(string category, IReadOnlyList<string> interests) =>
        interests.Count == 0 || interests.Any(interest =>
            string.Equals(interest.Trim(), category, StringComparison.OrdinalIgnoreCase) ||
            Categories.TryGetValue(interest.Trim(), out var matches) && matches.Contains(category, StringComparer.OrdinalIgnoreCase));

    public static string[] DiscoveryTypes(IReadOnlyList<string> interests)
    {
        var types = new List<string>();
        if (Allows("history", interests)) types.AddRange(["Q178561", "Q179700"]);
        if (Allows("architecture", interests)) types.Add("Q41176");
        if (Allows("culture", interests) || Allows("people", interests)) types.Add("Q179700");
        return types.Distinct().ToArray();
    }
}
