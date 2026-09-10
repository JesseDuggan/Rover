namespace Rover.Application.LocationIntelligence;

public enum PlaceIdentityMatchMethod
{
    ExplicitProviderIdentifier,
    SharedProviderIdentifier,
    ConservativeNameAndGeography,
    Unresolved
}

public enum EvidenceClaimType
{
    Fact,
    Inference,
    Unavailable
}

public enum StorySentenceContentType
{
    Fact,
    Inference,
    Unavailable
}

public enum StorySectionType
{
    CameraTeaser,
    Arrival,
    Deeper
}

public enum StoryAudienceProfile
{
    GeneralTraveller,
    HistoryEnthusiast,
    ArchitectureEnthusiast,
    FamilyWithChildren,
    LocalResident,
    BusinessTraveller,
    OutdoorAdventurer,
    AccessibilityFocused
}

public enum StoryCategory
{
    LocalHistory,
    NeighbourhoodHistory,
    Architecture,
    NotablePeople,
    Culture,
    FoodHistory,
    Nature,
    StrangeButVerified,
    FilmAndTelevision,
    ThenAndNow,
    NearbyEvents,
    CurrentLocalInformation,
    WeatherAndJourneyConditions
}

public enum StoryNarrationVariantType
{
    Quick,
    Standard,
    Deep
}

public enum StoryFreshnessClassification
{
    Evergreen,
    Expiring,
    Live,
    Mixed
}

public enum StoryNarrationStatus
{
    NotOffered,
    Offered,
    Playing,
    Interrupted,
    Completed,
    Skipped,
    Dismissed
}

public enum GroundingVerificationStatus
{
    Verified,
    Provisional,
    Unavailable,
    Rejected
}

public sealed record PlaceProviderIdentifiers(
    string? RoverId,
    string? GersId,
    string? WikidataQid,
    string? WikipediaPageId,
    string? GooglePlaceId,
    string? OpenStreetMapId,
    string? MapboxId,
    IReadOnlyDictionary<string, string> AdditionalIds);

public sealed record CanonicalPlaceIdentity(
    string CanonicalPlaceId,
    string Name,
    double Latitude,
    double Longitude,
    string? Address,
    IReadOnlyList<string> Categories,
    PlaceProviderIdentifiers ProviderIdentifiers,
    PlaceIdentityMatchMethod MatchMethod,
    double Confidence,
    DateTimeOffset VerifiedUtc);

public sealed record EvidenceSourceReference(
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

public sealed record EvidenceClaim(
    string EvidenceId,
    EvidenceClaimType ClaimType,
    string Text,
    IReadOnlyList<string> SourceIds,
    GroundingVerificationStatus VerificationStatus,
    double Confidence,
    DateTimeOffset RetrievedUtc,
    DateTimeOffset? ExpiresUtc)
{
    public string? Category { get; init; }
}

public sealed record GroundedStorySentence(
    string SentenceId,
    string Text,
    StorySentenceContentType ContentType,
    IReadOnlyList<string> EvidenceIds,
    double Confidence);

public sealed record GroundedStorySection(
    StorySectionType SectionType,
    IReadOnlyList<GroundedStorySentence> Sentences)
{
    public int TargetDurationSeconds { get; init; }
    public int EstimatedDurationSeconds { get; init; }
    public double Completeness { get; init; }
    public GroundingVerificationStatus Availability { get; init; }
}

public sealed record GroundingIssue(
    string Code,
    string Message,
    string? SentenceId,
    string? EvidenceId);

public sealed record GroundingValidationResult(
    bool IsValid,
    GroundingVerificationStatus Status,
    DateTimeOffset ValidatedUtc,
    IReadOnlyList<GroundingIssue> Issues);

public sealed record StoryGeographicAnchor(
    double Latitude,
    double Longitude,
    string? RouteId,
    string? RouteSegmentId,
    string? DirectionalContext);

public sealed record StoryNarrationVariant(
    string VariantId,
    StoryNarrationVariantType VariantType,
    StorySectionType SectionType,
    int TargetDurationSeconds,
    int EstimatedDurationSeconds,
    IReadOnlyList<string> SentenceIds,
    IReadOnlyList<string> EvidenceIds)
{
    public string? PrefetchedAudioReference { get; init; }
}

public sealed record StoryCacheEligibility(
    bool OfflineEligible,
    bool AudioCacheEligible,
    string RetentionClass,
    string Reason);

public sealed record StoryInteractionState(
    StoryNarrationStatus NarrationStatus,
    bool PreviouslyHeard,
    bool Completed,
    bool Skipped,
    bool Dismissed);

public sealed record StoryPack(
    string SchemaVersion,
    CanonicalPlaceIdentity? PlaceIdentity,
    string Profile,
    IReadOnlyList<GroundedStorySection> Sections,
    IReadOnlyList<EvidenceClaim> EvidenceClaims,
    IReadOnlyList<EvidenceSourceReference> Sources,
    double Confidence,
    double Completeness,
    IReadOnlyList<string> RequiredAttribution,
    DateTimeOffset GeneratedUtc,
    DateTimeOffset? ExpiresUtc,
    GroundingValidationResult? Validation)
{
    public DateTimeOffset? LastVerifiedUtc { get; init; }
    public IReadOnlyList<string> AvailableTopics { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> UnavailableTopics { get; init; } = Array.Empty<string>();
    public string? StoryId { get; init; }
    public string? EntityId { get; init; }
    public StoryGeographicAnchor? GeographicAnchor { get; init; }
    public StoryCategory? PrimaryCategory { get; init; }
    public IReadOnlyList<StoryCategory> Categories { get; init; } = Array.Empty<StoryCategory>();
    public IReadOnlyList<string> InterestTags { get; init; } = Array.Empty<string>();
    public IReadOnlyList<StoryNarrationVariant> NarrationVariants { get; init; } = Array.Empty<StoryNarrationVariant>();
    public double? EvidenceQualityScore { get; init; }
    public StoryFreshnessClassification? FreshnessClassification { get; init; }
    public DateTimeOffset? RetrievedUtc { get; init; }
    public StoryCacheEligibility? CacheEligibility { get; init; }
    public StoryInteractionState? InteractionState { get; init; }
    public IReadOnlyList<string> FollowUpPrompts { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> RelatedStoryPackIds { get; init; } = Array.Empty<string>();
}
