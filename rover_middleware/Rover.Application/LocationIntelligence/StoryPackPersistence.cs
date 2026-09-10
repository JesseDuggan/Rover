using System.Security.Cryptography;
using System.Text;

namespace Rover.Application.LocationIntelligence;

public sealed record StoryPackStorageKey(string Value)
{
    public static StoryPackStorageKey Create(
        string canonicalPlaceId,
        Guid? profileId,
        string? narrationStyle,
        IReadOnlyCollection<string> interests,
        string schemaVersion = "1.1")
    {
        var normalizedInterests = string.Join(",", interests
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim().ToLowerInvariant())
            .Distinct(StringComparer.Ordinal)
            .Order(StringComparer.Ordinal));
        var payload = string.Join("|",
            $"story-pack-{NormalizeSchemaVersion(schemaVersion)}",
            canonicalPlaceId.Trim().ToLowerInvariant(),
            profileId?.ToString("N") ?? "guest",
            narrationStyle?.Trim().ToLowerInvariant() ?? "default",
            normalizedInterests);
        return new StoryPackStorageKey(Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(payload))).ToLowerInvariant());
    }

    private static string NormalizeSchemaVersion(string schemaVersion)
        => string.Equals(schemaVersion?.Trim(), "2.0", StringComparison.Ordinal) ? "2.0" : "1.1";
}

public sealed record PersistedEvidenceSet(
    string CanonicalPlaceId,
    string SchemaVersion,
    IReadOnlyList<EvidenceClaim> Claims,
    IReadOnlyList<EvidenceSourceReference> Sources,
    DateTimeOffset StoredUtc,
    DateTimeOffset? ExpiresUtc);

public sealed record StoryPackPersistenceDecision(
    bool Allowed,
    string Reason,
    LocationStoryResult? Story,
    StoryPack? StoryPack);

public sealed class DefaultStoryPackPersistencePolicy : IStoryPackPersistencePolicy
{
    private readonly IStoryGroundingValidator _validator;
    private readonly LocationIntelligenceOptions _options;

    public DefaultStoryPackPersistencePolicy(
        IStoryGroundingValidator validator,
        LocationIntelligenceOptions options)
    {
        _validator = validator;
        _options = options;
    }

    public StoryPackPersistenceDecision Prepare(LocationStoryResult story, DateTimeOffset now)
    {
        if (story.StoryPack is null)
        {
            return Rejected("Story has no Story Pack.");
        }

        var packDecision = Prepare(story.StoryPack, now);
        if (!packDecision.Allowed || packDecision.StoryPack is null)
        {
            return packDecision;
        }

        var pack = packDecision.StoryPack;
        var arrival = pack.Sections.Single(section => section.SectionType == StorySectionType.Arrival);
        var deeper = pack.Sections.Single(section => section.SectionType == StorySectionType.Deeper);
        var shortNarration = SpokenText(arrival);
        var tellMeMore = SpokenText(deeper);
        var sourceProviders = pack.Sources
            .Select(source => (source.ProviderName, source.ProviderRecordId))
            .ToHashSet();
        var sources = story.SourceReferences
            .Where(source => sourceProviders.Contains((source.ProviderName, source.ProviderRecordId)))
            .ToArray();
        var persisted = story with
        {
            ShortSpokenNarration = shortNarration,
            TellMeMore = string.IsNullOrWhiteSpace(tellMeMore) ? null : tellMeMore,
            FactIdsUsed = story.FactIdsUsed
                .Where(id => pack.EvidenceClaims.Any(claim =>
                    claim.ClaimType == EvidenceClaimType.Fact
                    && string.Equals(claim.EvidenceId, id, StringComparison.OrdinalIgnoreCase)))
                .ToArray(),
            SourceReferences = sources,
            RequiredAttribution = pack.RequiredAttribution,
            SentenceGrounding = pack.Sections.SelectMany(section => section.Sentences).ToArray(),
            StorySections = pack.Sections,
            StoryPack = pack
        };
        return new StoryPackPersistenceDecision(true, packDecision.Reason, persisted, pack);
    }

    public StoryPackPersistenceDecision Prepare(StoryPack storyPack, DateTimeOffset now)
    {
        if (ContainsGoogleContent(storyPack))
        {
            return Rejected("Google Places content cannot be persisted; only its Place ID may be retained with non-Google evidence.");
        }

        if (storyPack.PlaceIdentity is null)
        {
            return Rejected("Story Pack has no canonical place identity.");
        }

        if (storyPack.SchemaVersion == "2.0" && storyPack.CacheEligibility?.OfflineEligible != true)
        {
            return Rejected("Story Pack 2.0 retention metadata does not permit offline persistence.");
        }

        var transientIds = storyPack.EvidenceClaims
            .Where(claim => IsTransient(claim) || IsLive(claim, now))
            .Select(claim => claim.EvidenceId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var claims = storyPack.EvidenceClaims
            .Where(claim => !transientIds.Contains(claim.EvidenceId))
            .ToArray();
        if (claims.Length == 0)
        {
            return Rejected("Story Pack has no offline-safe evidence after live claims were removed.");
        }
        var referencedSourceIds = claims.SelectMany(claim => claim.SourceIds)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var sources = storyPack.Sources
            .Where(source => referencedSourceIds.Contains(source.SourceId))
            .ToArray();
        var sections = storyPack.Sections
            .Select(section => RemoveTransientSentences(section, transientIds))
            .ToArray();
        if (sections.Length == 0)
        {
            return Rejected("Story Pack has no story sections.");
        }

        var expirationCandidates = claims
            .Select(claim => claim.ExpiresUtc)
            .Concat(sources.Select(source => source.ExpiresUtc))
            .Where(value => value is not null)
            .Select(value => value!.Value)
            .Append(now.AddMinutes(Math.Max(1, _options.GeneratedStoryCacheMinutes)))
            .ToArray();
        var expiresUtc = expirationCandidates.Min();
        if (expiresUtc <= now)
        {
            return Rejected("Story Pack evidence has expired.");
        }

        var requiredAttribution = sources
            .Select(source => source.Attribution)
            .Where(value => !string.IsNullOrWhiteSpace(value))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var prepared = storyPack with
        {
            Sections = sections,
            EvidenceClaims = claims,
            Sources = sources,
            RequiredAttribution = requiredAttribution,
            ExpiresUtc = expiresUtc,
            Validation = null,
            Completeness = sections.Average(section => section.Completeness),
            NarrationVariants = RebuildNarrationVariants(storyPack.StoryId, sections),
            EvidenceQualityScore = claims.Where(claim => claim.VerificationStatus == GroundingVerificationStatus.Verified)
                .Select(claim => (double?)claim.Confidence)
                .Average() ?? 0,
            FreshnessClassification = claims.All(claim => claim.ExpiresUtc is null || claim.ExpiresUtc > now.AddDays(3))
                ? StoryFreshnessClassification.Evergreen
                : StoryFreshnessClassification.Expiring,
            CacheEligibility = new StoryCacheEligibility(
                true,
                true,
                claims.All(claim => claim.ExpiresUtc is null || claim.ExpiresUtc > now.AddDays(3)) ? "evergreen" : "expiring",
                "Live and provider-restricted claims were removed before offline persistence.")
        };
        var validation = _validator.Validate(prepared, now);
        if (!validation.IsValid)
        {
            return Rejected("Story Pack failed persistence-time grounding validation.");
        }

        prepared = prepared with { Validation = validation };
        return new StoryPackPersistenceDecision(true, "Validated non-Google Story Pack is eligible for persistence.", null, prepared);
    }

    private static bool ContainsGoogleContent(StoryPack storyPack)
    {
        return storyPack.Sources.Any(source =>
                source.ProviderName.Contains("Google", StringComparison.OrdinalIgnoreCase)
                || source.SourceId.Contains("google", StringComparison.OrdinalIgnoreCase))
            || storyPack.RequiredAttribution.Any(value => value.Contains("Google Maps", StringComparison.OrdinalIgnoreCase));
    }

    private static bool IsTransient(EvidenceClaim claim)
    {
        return string.Equals(claim.Category, "relative_location", StringComparison.OrdinalIgnoreCase)
            || claim.EvidenceId.EndsWith(":relative-location", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsLive(EvidenceClaim claim, DateTimeOffset now)
    {
        if (claim.ExpiresUtc is { } expiry && expiry <= now.AddHours(24))
        {
            return true;
        }

        var category = claim.Category?.Trim().ToLowerInvariant() ?? string.Empty;
        return category is "opening_hours" or "business_hours" or "closure" or "price" or "pricing"
            or "weather" or "current_event" or "event" or "availability" or "current_information";
    }

    private static GroundedStorySection RemoveTransientSentences(
        GroundedStorySection section,
        IReadOnlySet<string> transientIds)
    {
        var sentences = section.Sentences
            .Where(sentence => !sentence.EvidenceIds.Any(transientIds.Contains))
            .ToArray();
        if (sentences.Length == 0)
        {
            sentences =
            [
                new GroundedStorySentence(
                    $"cached-{section.SectionType.ToString().ToLowerInvariant()}-unavailable",
                    "ROVER could not verify cached content for this section.",
                    StorySentenceContentType.Unavailable,
                    Array.Empty<string>(),
                    1)
            ];
        }

        return section with
        {
            Sentences = sentences,
            EstimatedDurationSeconds = EstimateDuration(sentences),
            Completeness = sentences.All(sentence => sentence.ContentType == StorySentenceContentType.Unavailable)
                ? 0
                : section.Completeness,
            Availability = sentences.All(sentence => sentence.ContentType == StorySentenceContentType.Unavailable)
                ? GroundingVerificationStatus.Unavailable
                : section.Availability
        };
    }

    private static int EstimateDuration(IEnumerable<GroundedStorySentence> sentences)
    {
        var words = sentences.Sum(sentence => sentence.Text.Split(' ', StringSplitOptions.RemoveEmptyEntries).Length);
        return Math.Max(1, (int)Math.Ceiling(words / 2.5d));
    }

    private static string SpokenText(GroundedStorySection section) =>
        string.Join(" ", section.Sentences.Select(sentence => sentence.Text));

    private static IReadOnlyList<StoryNarrationVariant> RebuildNarrationVariants(
        string? storyId,
        IReadOnlyList<GroundedStorySection> sections)
    {
        if (string.IsNullOrWhiteSpace(storyId))
        {
            return Array.Empty<StoryNarrationVariant>();
        }

        return sections.Select(section =>
        {
            var variantType = section.SectionType switch
            {
                StorySectionType.CameraTeaser => StoryNarrationVariantType.Quick,
                StorySectionType.Arrival => StoryNarrationVariantType.Standard,
                StorySectionType.Deeper => StoryNarrationVariantType.Deep,
                _ => StoryNarrationVariantType.Standard
            };
            return new StoryNarrationVariant(
                $"{storyId}:{variantType.ToString().ToLowerInvariant()}",
                variantType,
                section.SectionType,
                section.TargetDurationSeconds,
                section.EstimatedDurationSeconds,
                section.Sentences.Select(sentence => sentence.SentenceId).ToArray(),
                section.Sentences.SelectMany(sentence => sentence.EvidenceIds)
                    .Distinct(StringComparer.OrdinalIgnoreCase)
                    .ToArray());
        }).ToArray();
    }

    private static StoryPackPersistenceDecision Rejected(string reason) => new(false, reason, null, null);
}

public sealed class NullStoryPackRepository : IStoryPackRepository
{
    public Task<LocationStoryResult?> GetAsync(StoryPackStorageKey key, CancellationToken cancellationToken) =>
        Task.FromResult<LocationStoryResult?>(null);

    public Task<bool> StoreAsync(StoryPackStorageKey key, LocationStoryResult story, CancellationToken cancellationToken) =>
        Task.FromResult(false);
}

public sealed class NullEvidenceRepository : IEvidenceRepository
{
    public Task<PersistedEvidenceSet?> GetAsync(string canonicalPlaceId, CancellationToken cancellationToken) =>
        Task.FromResult<PersistedEvidenceSet?>(null);

    public Task<bool> StoreAsync(StoryPack storyPack, CancellationToken cancellationToken) => Task.FromResult(false);
}
