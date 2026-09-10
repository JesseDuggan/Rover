using Rover.Application.Adaptations;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Adaptations;

public sealed class MockNearbyDiscoveryProvider : INearbyDiscoveryProvider
{
    private static readonly IReadOnlyList<NearbyDiscovery> Catalog = new[]
    {
        new NearbyDiscovery(
            "discovery-coffee-maiden-lane",
            "Maiden Lane Espresso Window",
            "Coffee",
            new GeoLocation(37.7884, -122.4059),
            "A quick independent coffee pause close to the active route.",
            3,
            120,
            8,
            ContentSource.LocalRecommendation,
            null,
            null,
            new[] { "coffee", "food", "local" }),
        new NearbyDiscovery(
            "discovery-tea-grant-avenue",
            "Grant Avenue Tea Counter",
            "Tea",
            new GeoLocation(37.7895, -122.4055),
            "A calm tea stop just off the route with a short detour and indoor seating.",
            4,
            170,
            8,
            ContentSource.LocalRecommendation,
            null,
            null,
            new[] { "tea", "food", "local" }),
        new NearbyDiscovery(
            "discovery-cake-post-street",
            "Post Street Cake Slice",
            "Cakes",
            new GeoLocation(37.7887, -122.4087),
            "A compact dessert pause near the square when the walk wants something sweeter.",
            5,
            210,
            8,
            ContentSource.LocalRecommendation,
            null,
            null,
            new[] { "cake", "cakes", "dessert", "food" }),
        new NearbyDiscovery(
            "discovery-burger-geary",
            "Geary Burger Counter",
            "Burgers",
            new GeoLocation(37.7871, -122.4100),
            "A casual burger stop that makes sense for a longer food-forward detour.",
            7,
            310,
            12,
            ContentSource.LocalRecommendation,
            null,
            null,
            new[] { "burger", "burgers", "food" }),
        new NearbyDiscovery(
            "discovery-hobart-building",
            "Hobart Building Lobby",
            "Architecture",
            new GeoLocation(37.7891, -122.4048),
            "A compact architecture detour that matches design and city-history interests.",
            5,
            220,
            6,
            ContentSource.RoverEditorial,
            null,
            "Historic lobby access can vary by time of day.",
            new[] { "architecture", "history" }),
        new NearbyDiscovery(
            "discovery-interesting-belden-place",
            "Belden Place Alley",
            "Interesting Site",
            new GeoLocation(37.7914, -122.4039),
            "A tucked-away pedestrian lane that adds a small city-discovery moment.",
            6,
            280,
            6,
            ContentSource.RoverEditorial,
            null,
            null,
            new[] { "interesting", "sites", "hidden gems", "local", "history" }),
        new NearbyDiscovery(
            "discovery-heart-sculpture",
            "Union Square Heart Sculpture",
            "Public Art",
            new GeoLocation(37.7878, -122.4077),
            "A short public-art stop with almost no route penalty.",
            1,
            40,
            4,
            ContentSource.RoverEditorial,
            null,
            null,
            new[] { "public art", "art", "photo" }),
        new NearbyDiscovery(
            "discovery-movie-corner",
            "Classic Movie Corner",
            "Movie and Pop Culture",
            new GeoLocation(37.7867, -122.4066),
            "A nearby pop-culture reference point that fits a playful route extension.",
            4,
            180,
            5,
            ContentSource.LocalRecommendation,
            null,
            null,
            new[] { "movie", "pop culture", "local" }),
        new NearbyDiscovery(
            "discovery-scenic-terrace",
            "Compact Scenic Terrace",
            "Scenic Viewpoint",
            new GeoLocation(37.7893, -122.4072),
            "A small elevation change gives a better read on the square and skyline edges.",
            6,
            260,
            6,
            ContentSource.RoverEditorial,
            null,
            "Includes a steeper sidewalk segment.",
            new[] { "scenic", "view", "architecture" }),
        new NearbyDiscovery(
            "discovery-sponsored-walking-shop",
            "Sponsored Walking Shop",
            "Sponsored",
            new GeoLocation(37.7869, -122.4071),
            "A nearby retail stop for walking gear.",
            4,
            160,
            5,
            ContentSource.Sponsored,
            "Sponsored content: this recommendation is paid placement and is not Rover editorial content.",
            null,
            new[] { "shopping", "gear" })
    };

    public Task<IReadOnlyList<NearbyDiscovery>> FindAsync(
        WalkSession session,
        GeoLocation currentLocation,
        string? interest,
        IReadOnlyCollection<string> dismissedDiscoveryIds,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        var dismissed = dismissedDiscoveryIds.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var existing = session.Stops.Select(stop => stop.StopId).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var explicitInterest = string.IsNullOrWhiteSpace(interest) ? null : interest.Trim();
        var interests = session.Interests
            .Concat(explicitInterest is null ? Array.Empty<string>() : new[] { explicitInterest })
            .ToArray();

        var ranked = Catalog
            .Where(candidate => !dismissed.Contains(candidate.DiscoveryId))
            .Where(candidate => !existing.Contains(candidate.DiscoveryId))
            .Where(candidate => IsAccessible(session, candidate))
            .Select(candidate => new
            {
                Candidate = candidate,
                Score = Score(candidate, currentLocation, interests, explicitInterest)
            })
            .OrderByDescending(item => item.Score)
            .ThenBy(item => item.Candidate.ContentSource == ContentSource.Sponsored ? 1 : 0)
            .ThenBy(item => item.Candidate.AddedWalkingMinutes)
            .Select(item => item.Candidate)
            .ToArray();

        return Task.FromResult<IReadOnlyList<NearbyDiscovery>>(ranked);
    }

    private static bool IsAccessible(WalkSession session, NearbyDiscovery discovery)
    {
        if (!session.AccessibilityPreferences.Contains(AccessibilityPreference.AvoidStairs))
        {
            return true;
        }

        return discovery.AccessibilityLimitations?.Contains("steeper", StringComparison.OrdinalIgnoreCase) != true;
    }

    private static double Score(NearbyDiscovery discovery, GeoLocation currentLocation, IReadOnlyList<string> interests, string? explicitInterest)
    {
        var explicitScore = explicitInterest is not null && MatchesInterest(discovery, explicitInterest) ? 250 : 0;
        var interestScore = interests.Any(interest => discovery.InterestTags.Any(tag => tag.Contains(interest, StringComparison.OrdinalIgnoreCase) || interest.Contains(tag, StringComparison.OrdinalIgnoreCase)))
            ? 100
            : 0;
        var proximityScore = Math.Max(0, 60 - RouteMath.DistanceMeters(currentLocation, discovery.Location) / 10);
        var detourPenalty = discovery.AddedWalkingMinutes * 2 + discovery.AddedDistanceMeters / 80d;
        var sponsoredPenalty = discovery.ContentSource == ContentSource.Sponsored ? 20 : 0;
        return explicitScore + interestScore + proximityScore - detourPenalty - sponsoredPenalty;
    }

    private static bool MatchesInterest(NearbyDiscovery discovery, string interest)
    {
        return discovery.Category.Contains(interest, StringComparison.OrdinalIgnoreCase)
            || discovery.Name.Contains(interest, StringComparison.OrdinalIgnoreCase)
            || discovery.InterestTags.Any(tag => tag.Contains(interest, StringComparison.OrdinalIgnoreCase) || interest.Contains(tag, StringComparison.OrdinalIgnoreCase));
    }
}
