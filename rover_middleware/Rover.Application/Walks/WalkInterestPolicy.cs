using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public static class WalkInterestPolicy
{
    public static bool WantsFood(IEnumerable<string> interests) => interests.Any(IsFood);

    public static bool IsFood(string category)
    {
        var words = category.ToLowerInvariant().Replace('_', ' ').Split(' ', '-', '/', '&');
        return words.Any(word => word is "food" or "drink" or "drinks" or "dining" or "restaurant"
            or "restaurants" or "cafe" or "cafes" or "coffee" or "bakery" or "bar" or "pub"
            or "tea" or "cake" or "burger" or "café" or "cafés" or "bars" or "pubs" or "bakeries");
    }

    public static bool IsFood(WalkStop stop) =>
        stop.ContentType == ContentType.FoodAndDrink || IsFood(stop.Category);

    public static bool IsPerformanceVenue(string category)
    {
        var value = category.Trim().ToLowerInvariant().Replace('_', ' ');
        return value.Contains("theatre") || value.Contains("theater") || value is
            "concert hall" or "opera house" or "playhouse" or "cinema" or "live music venue" or "performing arts";
    }

    public static bool IsTicketOffice(string name, string category)
    {
        // Some ticket agents have the same provider category as the venue they serve.
        static bool Matches(string label) => System.Text.RegularExpressions.Regex.IsMatch(label,
            @"\b(?:box[\s-]*office|ticket(?:ing)?[\s-]*(?:office|agency|agent|outlet|counter|service)|ticketking|ticketmaster|billetterie|taquilla|biglietteria|kartenverkauf)\b",
            System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.CultureInvariant);
        return Matches(name) || Matches(category);
    }

    public static string Group(string category)
    {
        if (IsFood(category)) return "food";
        var words = category.ToLowerInvariant().Split([' ', '-', '/', '&', '_'], StringSplitOptions.RemoveEmptyEntries);
        if (IsPerformanceVenue(category) || words.Any(word => word is "culture" or "film" or "movies" or "music")) return "culture";
        if (words.Any(word => word is "architecture" or "architectural" or "building" or "buildings" or "cathedral" or "church")) return "architecture";
        if (words.Any(word => word is "art" or "arts" or "gallery" or "sculpture" or "mural")) return "art";
        if (words.Any(word => word is "park" or "parks" or "garden" or "gardens" or "nature" or "outdoors" or "outdoor" or "trail" or "beach")) return "nature";
        if (words.Any(word => word is "history" or "historic" or "historical" or "heritage" or "museum" or "monument" or "landmark")) return "history";
        if (words.Any(word => word is "shopping" or "retail" or "shop" or "market")) return "shopping";
        return category.Trim().ToLowerInvariant();
    }

    public static string Group(WalkStop stop) => IsFood(stop) ? "food" : IsPerformanceVenue(stop.Category) ? "culture" : stop.ContentType switch
    {
        ContentType.Architecture => "architecture",
        ContentType.PublicArt => "art",
        ContentType.Shopping => "shopping",
        _ => Group(stop.Category)
    };

    // The first candidate in each requested group precedes the second in any
    // group. Original rank breaks ties and determines the final ordering.
    public static T[] TakeBalanced<T>(IEnumerable<T> ranked, int limit,
        IReadOnlyCollection<string> interests, Func<T, string> groupFor,
        IEnumerable<string>? existingGroups = null)
    {
        var counts = interests.Select(Group).Distinct().ToDictionary(group => group, _ => 0);
        var totalSlots = limit;
        foreach (var group in existingGroups ?? [])
        {
            totalSlots++;
            if (counts.ContainsKey(group)) counts[group]++;
        }
        var foodShare = (int)Math.Ceiling(totalSlots / (double)Math.Max(1, counts.Count));
        var priorities = new List<(T Item, int Round, int Rank)>();
        foreach (var item in ranked)
        {
            var group = groupFor(item);
            if (group == "food" && !counts.ContainsKey(group)) continue;
            var round = int.MaxValue - 1;
            if (counts.TryGetValue(group, out var count))
            {
                // Other available sights still precede surplus food when the
                // provider cannot identify their precise non-food category.
                round = group == "food" && counts.Count > 1 && count >= foodShare ? int.MaxValue : count;
                counts[group]++;
            }
            priorities.Add((item, round, priorities.Count));
        }
        return priorities.OrderBy(entry => entry.Round).ThenBy(entry => entry.Rank).Take(limit)
            .OrderBy(entry => entry.Rank).Select(entry => entry.Item).ToArray();
    }

    public static bool Allows(WalkStop stop, IEnumerable<string> interests) =>
        !IsTicketOffice(stop.Name, stop.Category) && (!IsFood(stop) || (interests.Any(value => IsFood(value) && !IsCoffee(value))
            || (interests.Any(IsCoffee) && IsCoffee(stop.Category))));

    public static bool IsCoffee(string value) =>
        value.Contains("coffee", StringComparison.OrdinalIgnoreCase) ||
        value.Contains("cafe", StringComparison.OrdinalIgnoreCase) ||
        value.Contains("caf�", StringComparison.OrdinalIgnoreCase);
}
