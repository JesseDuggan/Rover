using Rover.Domain.Walks;

namespace Rover.Application.Adaptations;

public sealed record NearbyDiscovery(
    string DiscoveryId,
    string Name,
    string Category,
    GeoLocation Location,
    string WhyRecommended,
    int AddedWalkingMinutes,
    int AddedDistanceMeters,
    int EstimatedVisitMinutes,
    ContentSource ContentSource,
    string? SponsoredDisclosure,
    string? AccessibilityLimitations,
    IReadOnlyCollection<string> InterestTags,
    string? Address = null,
    string? WebsiteUrl = null,
    string? PhoneNumber = null,
    string? MenuUrl = null,
    string? DiscoveryProviderName = null,
    string? ProviderPlaceId = null,
    string? SourceUrl = null,
    IReadOnlyCollection<string>? RequiredAttribution = null)
{
    public WalkStop ToStop(int sequenceNumber)
    {
        return new WalkStop(
            DiscoveryId,
            sequenceNumber,
            Name,
            Location,
            WhyRecommended,
            SponsoredDisclosure is null
                ? WhyRecommended
                : $"{WhyRecommended} {SponsoredDisclosure}",
            Category,
            ToContentType(),
            ContentSource,
            EstimatedVisitMinutes,
            AddedDistanceMeters,
            WalkGeofenceDefaults.StandardArrivalRadiusMeters,
            SponsoredDisclosure,
            Address,
            WebsiteUrl,
            PhoneNumber,
            MenuUrl,
            DiscoveryProviderName,
            ProviderPlaceId,
            SourceUrl,
            RequiredAttribution);
    }

    private ContentType ToContentType()
    {
        if (ContentSource == ContentSource.Sponsored)
        {
            return ContentType.SponsoredRecommendation;
        }

        var category = Category.ToLowerInvariant();
        if (category.Contains("coffee") || category.Contains("tea") || category.Contains("cake") || category.Contains("burger"))
        {
            return ContentType.FoodAndDrink;
        }

        if (category.Contains("art"))
        {
            return ContentType.PublicArt;
        }

        if (category.Contains("architecture"))
        {
            return ContentType.Architecture;
        }

        return ContentType.History;
    }
}
