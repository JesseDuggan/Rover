namespace Rover.Api.Contracts;

public sealed record LocationStoryRequest(
    double Latitude,
    double Longitude,
    int? RadiusMeters,
    string? RouteId,
    Guid? ProfileId,
    IReadOnlyList<RouteCoordinateResponse>? RouteGeometry,
    IReadOnlyList<string>? Interests,
    IReadOnlyList<string>? SelectedPlaceIds,
    string? NarrationStyle)
{
    public string? RouteSegmentId { get; init; }
    public string? DirectionalContext { get; init; }
}

public sealed record LocationStoryResponse(
    string StoryTitle,
    string ShortSpokenNarration,
    string? TellMeMore,
    string? PlaceId,
    IReadOnlyList<string> FactIdsUsed,
    IReadOnlyList<LocationSourceResponse> SourceReferences,
    double Confidence,
    IReadOnlyList<string> RequiredAttribution,
    IReadOnlyList<string> Warnings)
{
    public StoryPackResponse? StoryPack { get; init; }
}

public sealed record StoryPackResponse(
    string SchemaVersion,
    CanonicalPlaceIdentityResponse? PlaceIdentity,
    string Profile,
    IReadOnlyList<GroundedStorySectionResponse> Sections,
    IReadOnlyList<EvidenceClaimResponse> EvidenceClaims,
    IReadOnlyList<EvidenceSourceReferenceResponse> Sources,
    double Confidence,
    double Completeness,
    IReadOnlyList<string> RequiredAttribution,
    DateTimeOffset GeneratedUtc,
    DateTimeOffset? ExpiresUtc,
    GroundingValidationResponse? Validation)
{
    public DateTimeOffset? LastVerifiedUtc { get; init; }
    public IReadOnlyList<string> AvailableTopics { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> UnavailableTopics { get; init; } = Array.Empty<string>();
    public string? StoryId { get; init; }
    public string? EntityId { get; init; }
    public StoryGeographicAnchorResponse? GeographicAnchor { get; init; }
    public string? PrimaryCategory { get; init; }
    public IReadOnlyList<string> Categories { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> InterestTags { get; init; } = Array.Empty<string>();
    public IReadOnlyList<StoryNarrationVariantResponse> NarrationVariants { get; init; } = Array.Empty<StoryNarrationVariantResponse>();
    public double? EvidenceQualityScore { get; init; }
    public string? FreshnessClassification { get; init; }
    public DateTimeOffset? RetrievedUtc { get; init; }
    public StoryCacheEligibilityResponse? CacheEligibility { get; init; }
    public StoryInteractionStateResponse? InteractionState { get; init; }
    public IReadOnlyList<string> FollowUpPrompts { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> RelatedStoryPackIds { get; init; } = Array.Empty<string>();
}

public sealed record StoryGeographicAnchorResponse(
    double Latitude,
    double Longitude,
    string? RouteId,
    string? RouteSegmentId,
    string? DirectionalContext);

public sealed record StoryNarrationVariantResponse(
    string VariantId,
    string VariantType,
    string SectionType,
    int TargetDurationSeconds,
    int EstimatedDurationSeconds,
    IReadOnlyList<string> SentenceIds,
    IReadOnlyList<string> EvidenceIds,
    string? PrefetchedAudioReference);

public sealed record StoryCacheEligibilityResponse(
    bool OfflineEligible,
    bool AudioCacheEligible,
    string RetentionClass,
    string Reason);

public sealed record StoryInteractionStateResponse(
    string NarrationStatus,
    bool PreviouslyHeard,
    bool Completed,
    bool Skipped,
    bool Dismissed);

public sealed record CanonicalPlaceIdentityResponse(
    string CanonicalPlaceId,
    string Name,
    double Latitude,
    double Longitude,
    string? Address,
    IReadOnlyList<string> Categories,
    PlaceProviderIdentifiersResponse ProviderIdentifiers,
    string MatchMethod,
    double Confidence,
    DateTimeOffset VerifiedUtc);

public sealed record PlaceProviderIdentifiersResponse(
    string? RoverId,
    string? GersId,
    string? WikidataQid,
    string? WikipediaPageId,
    string? GooglePlaceId,
    string? OpenStreetMapId,
    string? MapboxId,
    IReadOnlyDictionary<string, string> AdditionalIds);

public sealed record EvidenceSourceReferenceResponse(
    string SourceId,
    string ProviderName,
    string? ProviderRecordId,
    string? SourceTitle,
    string? SourceUrl,
    string Attribution,
    string? License,
    DateTimeOffset RetrievedUtc,
    DateTimeOffset? ExpiresUtc,
    double Confidence);

public sealed record EvidenceClaimResponse(
    string EvidenceId,
    string ClaimType,
    string Text,
    IReadOnlyList<string> SourceIds,
    string VerificationStatus,
    double Confidence,
    DateTimeOffset RetrievedUtc,
    DateTimeOffset? ExpiresUtc)
{
    public string? Category { get; init; }
}

public sealed record GroundedStorySectionResponse(
    string SectionType,
    IReadOnlyList<GroundedStorySentenceResponse> Sentences)
{
    public int TargetDurationSeconds { get; init; }
    public int EstimatedDurationSeconds { get; init; }
    public double Completeness { get; init; }
    public string Availability { get; init; } = "Unavailable";
}

public sealed record GroundedStorySentenceResponse(
    string SentenceId,
    string Text,
    string ContentType,
    IReadOnlyList<string> EvidenceIds,
    double Confidence);

public sealed record GroundingValidationResponse(
    bool IsValid,
    string Status,
    DateTimeOffset ValidatedUtc,
    IReadOnlyList<GroundingIssueResponse> Issues);

public sealed record GroundingIssueResponse(
    string Code,
    string Message,
    string? SentenceId,
    string? EvidenceId);

public sealed record LocationStoryContextResponse(
    LocationResponse UserCoordinates,
    int SearchRadiusMeters,
    string? RouteOrWalkId,
    Guid? ProfileId,
    DateTimeOffset GeneratedUtc,
    IReadOnlyList<LocationPlaceResponse> RankedPlaces,
    WeatherTimeContextResponse? WeatherTimeContext,
    IReadOnlyList<string> SourceWarnings,
    IReadOnlyList<LocationProviderStatusResponse> ProviderStatus,
    LocationCacheStatusResponse CacheStatus);

public sealed record LocationPlaceResponse(
    string CanonicalId,
    string Name,
    LocationResponse Coordinates,
    string? Address,
    IReadOnlyList<string> Categories,
    string? ShortDescription,
    IReadOnlyList<LocationFactResponse> Facts,
    IReadOnlyList<LocationSourceResponse> SourceReferences,
    IReadOnlyDictionary<string, string> ProviderIds,
    double? DistanceFromUserMeters,
    double? DistanceFromRouteMeters,
    int? EstimatedDetourMinutes,
    string? DirectionFromUser,
    double ConfidenceScore,
    double StoryWorthinessScore,
    IReadOnlyList<string> StoryWorthinessReasons,
    IReadOnlyList<LocationImageReferenceResponse> ImageReferences,
    string? OpeningStatus,
    string? AccessibilityInformation,
    DateTimeOffset LastRefreshedUtc)
{
    public PlaceIdentityResolutionResponse? IdentityResolution { get; init; }
}

public sealed record PlaceIdentityResolutionResponse(
    string MatchMethod,
    string VerificationStatus,
    double Confidence,
    IReadOnlyList<PlaceIdentityCandidateResponse> Candidates,
    DateTimeOffset ResolvedUtc);

public sealed record PlaceIdentityCandidateResponse(
    string ProviderName,
    string ProviderRecordId,
    string? WikidataQid,
    double Confidence);

public sealed record LocationFactResponse(
    string FactId,
    string FactType,
    string FactText,
    LocationSourceResponse Source,
    double ConfidenceScore,
    bool IsSuitableForNarration,
    DateTimeOffset RetrievedUtc);

public sealed record LocationSourceResponse(
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

public sealed record LocationImageReferenceResponse(string Url, string? Caption, LocationSourceResponse Source);

public sealed record WeatherTimeContextResponse(
    string? Summary,
    string? Temperature,
    string? Conditions,
    DateTimeOffset? ObservedUtc,
    LocationSourceResponse? Source);

public sealed record LocationProviderStatusResponse(
    string ProviderName,
    bool Enabled,
    bool Succeeded,
    bool CacheHit,
    int ResultCount,
    long LatencyMilliseconds,
    string? Warning);

public sealed record LocationCacheStatusResponse(string CacheKey, bool Hit, DateTimeOffset? ExpiresUtc);
