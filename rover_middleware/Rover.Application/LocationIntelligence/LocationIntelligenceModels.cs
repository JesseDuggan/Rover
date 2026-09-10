using Rover.Domain.Walks;

namespace Rover.Application.LocationIntelligence;

public sealed record LocationContextQuery(
    GeoLocation UserLocation,
    int RadiusMeters,
    string? RouteId,
    Guid? ProfileId,
    IReadOnlyList<GeoLocation> RouteGeometry,
    IReadOnlyCollection<string> Interests)
{
    public string? RouteSegmentId { get; init; }
    public string? DirectionalContext { get; init; }
}

public sealed record LocationSource(
    string ProviderName,
    string? ProviderRecordId,
    string? SourceUrl,
    string Attribution,
    string? License,
    DateTimeOffset RetrievedUtc,
    double ConfidenceScore)
{
    public string? SourceTitle { get; init; }
    public DateTimeOffset? ExpiresUtc { get; init; }
}

public sealed record LocationFact(
    string FactId,
    string FactType,
    string FactText,
    LocationSource Source,
    double ConfidenceScore,
    bool IsSuitableForNarration,
    DateTimeOffset RetrievedUtc);

public sealed record LocationImageReference(
    string Url,
    string? Caption,
    LocationSource Source);

public sealed record PlaceIdentityCandidate(
    string ProviderName,
    string ProviderRecordId,
    string? WikidataQid,
    double Confidence);

public sealed record PlaceIdentityResolution(
    PlaceIdentityMatchMethod MatchMethod,
    GroundingVerificationStatus VerificationStatus,
    double Confidence,
    IReadOnlyList<PlaceIdentityCandidate> Candidates,
    DateTimeOffset ResolvedUtc);

public sealed record LocationPlace(
    string CanonicalId,
    string Name,
    GeoLocation Coordinates,
    string? Address,
    IReadOnlyList<string> Categories,
    string? ShortDescription,
    IReadOnlyList<LocationFact> Facts,
    IReadOnlyList<LocationSource> SourceReferences,
    IReadOnlyDictionary<string, string> ProviderIds,
    double? DistanceFromUserMeters,
    double? DistanceFromRouteMeters,
    int? EstimatedDetourMinutes,
    string? DirectionFromUser,
    double ConfidenceScore,
    double StoryWorthinessScore,
    IReadOnlyList<string> StoryWorthinessReasons,
    IReadOnlyList<LocationImageReference> ImageReferences,
    string? OpeningStatus,
    string? AccessibilityInformation,
    DateTimeOffset LastRefreshedUtc)
{
    public PlaceIdentityResolution? IdentityResolution { get; init; }
    public string? City { get; init; }
    public string? Region { get; init; }
    public string? CountryCode { get; init; }
}

public sealed record WeatherTimeContext(
    string? Summary,
    string? Temperature,
    string? Conditions,
    DateTimeOffset? ObservedUtc,
    LocationSource? Source);

public sealed record LocationProviderStatus(
    string ProviderName,
    bool Enabled,
    bool Succeeded,
    bool CacheHit,
    int ResultCount,
    long LatencyMilliseconds,
    string? Warning);

public sealed record LocationCacheStatus(string CacheKey, bool Hit, DateTimeOffset? ExpiresUtc);

public sealed record LocationStoryContext(
    GeoLocation UserCoordinates,
    int SearchRadiusMeters,
    string? RouteOrWalkId,
    Guid? ProfileId,
    DateTimeOffset GeneratedUtc,
    IReadOnlyList<LocationPlace> RankedPlaces,
    WeatherTimeContext? WeatherTimeContext,
    IReadOnlyList<string> SourceWarnings,
    IReadOnlyList<LocationProviderStatus> ProviderStatus,
    LocationCacheStatus CacheStatus)
{
    public string? RouteSegmentId { get; init; }
    public string? DirectionalContext { get; init; }
}

public sealed record LocationStoryRequest(
    GeoLocation UserCoordinates,
    int RadiusMeters,
    string? RouteId,
    Guid? ProfileId,
    IReadOnlyList<GeoLocation> RouteGeometry,
    IReadOnlyCollection<string> Interests,
    IReadOnlyCollection<string> SelectedPlaceIds,
    string? NarrationStyle)
{
    public string? RouteSegmentId { get; init; }
    public string? DirectionalContext { get; init; }
}

public sealed record LocationStoryResult(
    string StoryTitle,
    string ShortSpokenNarration,
    string? TellMeMore,
    string? PlaceId,
    IReadOnlyList<string> FactIdsUsed,
    IReadOnlyList<LocationSource> SourceReferences,
    double Confidence,
    IReadOnlyList<string> RequiredAttribution,
    IReadOnlyList<string> Warnings)
{
    public IReadOnlyList<GroundedStorySentence> SentenceGrounding { get; init; } = Array.Empty<GroundedStorySentence>();
    public IReadOnlyList<GroundedStorySection> StorySections { get; init; } = Array.Empty<GroundedStorySection>();
    public StoryPack? StoryPack { get; init; }
}

public sealed record LocationContextProviderResult(
    string ProviderName,
    bool Enabled,
    IReadOnlyList<LocationPlace> Places,
    WeatherTimeContext? WeatherTimeContext,
    IReadOnlyList<string> Warnings,
    bool CacheHit,
    long LatencyMilliseconds);
