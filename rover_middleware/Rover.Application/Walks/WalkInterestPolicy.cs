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
            or "tea" or "cake" or "burger");
    }

    public static bool Allows(WalkStop stop, IEnumerable<string> interests) =>
        WantsFood(interests) || (stop.ContentType != ContentType.FoodAndDrink && !IsFood(stop.Category));
}
