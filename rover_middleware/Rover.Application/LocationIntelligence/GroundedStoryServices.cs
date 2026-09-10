using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using Rover.Application.Journeys;

namespace Rover.Application.LocationIntelligence;

public sealed class DeterministicStoryPackFactory : IStoryPackFactory
{
    private readonly TimeSpan _evidenceFreshness;
    private readonly TimeSpan _spatialEvidenceFreshness;
    private readonly bool _storyPackV2Enabled;

    public DeterministicStoryPackFactory(LocationIntelligenceOptions options, Phase15Options? phase15Options = null)
    {
        _evidenceFreshness = TimeSpan.FromMinutes(Math.Max(1, options.EvidenceFreshnessMinutes));
        _spatialEvidenceFreshness = TimeSpan.FromMinutes(Math.Max(1, options.SpatialEvidenceFreshnessMinutes));
        _storyPackV2Enabled = phase15Options?.Enabled == true && phase15Options.StoryPackV2Enabled;
    }

    public string SchemaVersion => _storyPackV2Enabled ? "2.0" : "1.1";

    public StoryPack Create(
        LocationStoryContext context,
        LocationStoryResult story,
        string? narrationStyle,
        IReadOnlyCollection<string> interests,
        DateTimeOffset now)
    {
        var place = context.RankedPlaces.FirstOrDefault(candidate =>
            string.Equals(candidate.CanonicalId, story.PlaceId, StringComparison.OrdinalIgnoreCase));
        var sourceMap = BuildSources(place, story.SourceReferences);
        var claims = BuildClaims(place, sourceMap, now);
        var profile = ResolveProfile(narrationStyle, interests);
        var sentences = story.SentenceGrounding.Count > 0
            ? story.SentenceGrounding
            : BuildSentenceGrounding(story, place, claims);
        var sections = BuildSections(story, sentences, claims, profile);
        if (_storyPackV2Enabled)
        {
            sections = sections.Select(section => section.SectionType == StorySectionType.CameraTeaser
                ? DecorateSection(section, 15)
                : section).ToArray();
        }
        var expiresUtc = claims.Where(claim => claim.ExpiresUtc is not null)
            .Select(claim => claim.ExpiresUtc)
            .Min();
        var allSentences = sections.SelectMany(section => section.Sentences).ToArray();
        var citedEvidenceIds = allSentences.SelectMany(sentence => sentence.EvidenceIds)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Count();
        var completeness = sections.Count == 0
            ? 0
            : sections.Average(section => section.Completeness);
        var availableTopics = claims
            .Where(claim => claim.ClaimType == EvidenceClaimType.Fact && claim.VerificationStatus == GroundingVerificationStatus.Verified)
            .Select(TopicFor)
            .Where(topic => topic is not null)
            .Cast<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var allTopics = new[] { "Accessibility", "Architecture", "History", "Media", "People", "Practical information", "Surprising detail" };

        var identity = place is null ? null : CreateIdentity(place, now);
        var pack = new StoryPack(
            SchemaVersion,
            identity,
            profile.ToString(),
            sections,
            claims,
            sourceMap.Values.OrderBy(source => source.SourceId, StringComparer.Ordinal).ToArray(),
            Math.Clamp(story.Confidence, 0, 1),
            Math.Clamp(completeness * (citedEvidenceIds == 0 && allSentences.Any(sentence => sentence.ContentType != StorySentenceContentType.Unavailable) ? 0.5 : 1), 0, 1),
            story.RequiredAttribution,
            now,
            expiresUtc,
            null)
        {
            LastVerifiedUtc = claims
                .Where(claim => claim.VerificationStatus == GroundingVerificationStatus.Verified)
                .Select(claim => (DateTimeOffset?)claim.RetrievedUtc)
                .Max(),
            AvailableTopics = availableTopics,
            UnavailableTopics = allTopics.Except(availableTopics, StringComparer.OrdinalIgnoreCase).ToArray()
        };

        return _storyPackV2Enabled
            ? AddVersion2Metadata(pack, context, place, claims, sections, interests, now)
            : pack;
    }

    private static StoryPack AddVersion2Metadata(
        StoryPack pack,
        LocationStoryContext context,
        LocationPlace? place,
        IReadOnlyList<EvidenceClaim> claims,
        IReadOnlyList<GroundedStorySection> sections,
        IReadOnlyCollection<string> interests,
        DateTimeOffset now)
    {
        var entityId = place?.CanonicalId ?? "unresolved";
        var evidenceIds = claims.Select(claim => claim.EvidenceId)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var storyId = StableStoryId(entityId, pack.Profile, evidenceIds);
        var categories = claims
            .Where(claim => claim.ClaimType == EvidenceClaimType.Fact)
            .Select(CategoryFor)
            .Distinct()
            .ToArray();
        if (categories.Length == 0)
        {
            categories = [StoryCategory.LocalHistory];
        }

        var containsRestrictedProvider = pack.Sources.Any(source =>
            source.ProviderName.Contains("Google", StringComparison.OrdinalIgnoreCase)
            || source.SourceId.Contains("google", StringComparison.OrdinalIgnoreCase));
        var freshness = FreshnessFor(claims, now);
        var variants = sections.Select(section => new StoryNarrationVariant(
            $"{storyId}:{VariantTypeFor(section.SectionType).ToString().ToLowerInvariant()}",
            VariantTypeFor(section.SectionType),
            section.SectionType,
            section.TargetDurationSeconds,
            section.EstimatedDurationSeconds,
            section.Sentences.Select(sentence => sentence.SentenceId).ToArray(),
            section.Sentences.SelectMany(sentence => sentence.EvidenceIds)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray())).ToArray();
        var verifiedClaims = claims.Where(claim => claim.VerificationStatus == GroundingVerificationStatus.Verified).ToArray();
        var evidenceQuality = verifiedClaims.Length == 0 ? 0 : verifiedClaims.Average(claim => claim.Confidence);
        var tags = interests.Where(value => !string.IsNullOrWhiteSpace(value))
            .Select(value => value.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var followUps = categories.Take(3)
            .Select(category => $"Tell me more about {CategoryLabel(category)}.")
            .ToArray();

        return pack with
        {
            StoryId = storyId,
            EntityId = entityId,
            GeographicAnchor = place is null ? null : new StoryGeographicAnchor(
                place.Coordinates.Latitude,
                place.Coordinates.Longitude,
                context.RouteOrWalkId,
                context.RouteSegmentId,
                context.DirectionalContext ?? place.DirectionFromUser),
            PrimaryCategory = categories[0],
            Categories = categories,
            InterestTags = tags,
            NarrationVariants = variants,
            EvidenceQualityScore = Math.Round(Math.Clamp(evidenceQuality, 0, 1), 3),
            FreshnessClassification = freshness,
            RetrievedUtc = pack.Sources.Count == 0 ? now : pack.Sources.Max(source => source.RetrievedUtc),
            CacheEligibility = new StoryCacheEligibility(
                !containsRestrictedProvider && freshness is not StoryFreshnessClassification.Live,
                !containsRestrictedProvider && freshness is StoryFreshnessClassification.Evergreen or StoryFreshnessClassification.Expiring,
                freshness.ToString().ToLowerInvariant(),
                containsRestrictedProvider
                    ? "Provider retention policy prohibits offline persistence."
                    : freshness == StoryFreshnessClassification.Live
                        ? "Live information must not be retained for offline narration."
                        : freshness == StoryFreshnessClassification.Mixed
                            ? "Mixed content may persist only after live claims are removed; generated audio is not reusable."
                            : "Validated evidence is eligible for bounded caching."),
            InteractionState = new StoryInteractionState(StoryNarrationStatus.NotOffered, false, false, false, false),
            FollowUpPrompts = followUps,
            RelatedStoryPackIds = Array.Empty<string>()
        };
    }

    private static string StableStoryId(string entityId, string profile, IEnumerable<string> evidenceIds)
    {
        var payload = $"story-pack-2.0|{entityId.Trim().ToLowerInvariant()}|{profile.Trim().ToLowerInvariant()}|{string.Join(',', evidenceIds)}";
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(payload))).ToLowerInvariant();
        return $"story:{hash[..24]}";
    }

    private static StoryNarrationVariantType VariantTypeFor(StorySectionType sectionType) => sectionType switch
    {
        StorySectionType.CameraTeaser => StoryNarrationVariantType.Quick,
        StorySectionType.Arrival => StoryNarrationVariantType.Standard,
        StorySectionType.Deeper => StoryNarrationVariantType.Deep,
        _ => StoryNarrationVariantType.Standard
    };

    private static StoryFreshnessClassification FreshnessFor(IReadOnlyList<EvidenceClaim> claims, DateTimeOffset now)
    {
        if (claims.Count == 0) return StoryFreshnessClassification.Expiring;
        var live = claims.Count(claim => claim.ExpiresUtc is { } expiry && expiry <= now.AddHours(24));
        var evergreen = claims.Count(claim => claim.ExpiresUtc is null || claim.ExpiresUtc > now.AddDays(3));
        if (live == claims.Count) return StoryFreshnessClassification.Live;
        if (evergreen == claims.Count) return StoryFreshnessClassification.Evergreen;
        if (live > 0 && evergreen > 0) return StoryFreshnessClassification.Mixed;
        return StoryFreshnessClassification.Expiring;
    }

    private static StoryCategory CategoryFor(EvidenceClaim claim)
    {
        var value = $"{claim.Category} {claim.Text}".ToLowerInvariant();
        if (ContainsAny(value, "weather", "temperature", "rain", "snow", "wind")) return StoryCategory.WeatherAndJourneyConditions;
        if (ContainsAny(value, "event", "festival", "concert")) return StoryCategory.NearbyEvents;
        if (ContainsAny(value, "hours", "closure", "current", "today")) return StoryCategory.CurrentLocalInformation;
        if (ContainsAny(value, "film", "movie", "television")) return StoryCategory.FilmAndTelevision;
        if (ContainsAny(value, "architect", "building", "design", "style")) return StoryCategory.Architecture;
        if (ContainsAny(value, "person", "people", "founder", "born")) return StoryCategory.NotablePeople;
        if (ContainsAny(value, "food", "restaurant", "cafe", "brewery")) return StoryCategory.FoodHistory;
        if (ContainsAny(value, "park", "river", "lake", "nature", "trail")) return StoryCategory.Nature;
        if (ContainsAny(value, "culture", "community", "tradition")) return StoryCategory.Culture;
        if (ContainsAny(value, "unusual", "strange", "surprising", "largest", "oldest", "first")) return StoryCategory.StrangeButVerified;
        if (ContainsAny(value, "then", "today", "replaced", "formerly")) return StoryCategory.ThenAndNow;
        if (ContainsAny(value, "neighbourhood", "neighborhood", "district")) return StoryCategory.NeighbourhoodHistory;
        return StoryCategory.LocalHistory;
    }

    private static string CategoryLabel(StoryCategory category)
        => Regex.Replace(category.ToString(), "([a-z])([A-Z])", "$1 $2").ToLowerInvariant();

    private IReadOnlyDictionary<string, EvidenceSourceReference> BuildSources(LocationPlace? place, IReadOnlyList<LocationSource> storySources)
    {
        var sources = (place?.SourceReferences ?? Array.Empty<LocationSource>())
            .Concat(place?.Facts.Select(fact => fact.Source) ?? Array.Empty<LocationSource>())
            .Concat(storySources)
            .GroupBy(SourceKey, StringComparer.OrdinalIgnoreCase)
            .Select(group => group.OrderByDescending(source => source.ConfidenceScore).First())
            .ToDictionary(
                SourceKey,
                source => new EvidenceSourceReference(
                    StableSourceId(source),
                    source.ProviderName,
                    source.ProviderRecordId,
                    source.SourceTitle,
                    source.SourceUrl,
                    source.Attribution,
                    source.License,
                    source.RetrievedUtc,
                    source.ExpiresUtc ?? source.RetrievedUtc.Add(_evidenceFreshness),
                    Math.Clamp(source.ConfidenceScore, 0, 1)),
                StringComparer.OrdinalIgnoreCase);
        return sources;
    }

    private IReadOnlyList<EvidenceClaim> BuildClaims(
        LocationPlace? place,
        IReadOnlyDictionary<string, EvidenceSourceReference> sources,
        DateTimeOffset now)
    {
        if (place is null)
        {
            return Array.Empty<EvidenceClaim>();
        }

        var claims = place.Facts.Select(fact =>
        {
            var sourceId = sources.TryGetValue(SourceKey(fact.Source), out var source) ? source.SourceId : null;
            var expiresUtc = fact.Source.ExpiresUtc ?? fact.RetrievedUtc.Add(_evidenceFreshness);
            return new EvidenceClaim(
                fact.FactId,
                EvidenceClaimType.Fact,
                fact.FactText,
                sourceId is null ? Array.Empty<string>() : new[] { sourceId },
                fact.IsSuitableForNarration && fact.ConfidenceScore >= 0.6 && expiresUtc > now
                    ? GroundingVerificationStatus.Verified
                    : GroundingVerificationStatus.Provisional,
                Math.Clamp(fact.ConfidenceScore, 0, 1),
                fact.RetrievedUtc,
                expiresUtc)
            {
                Category = fact.FactType
            };
        }).ToList();

        var placeSourceIds = place.SourceReferences
            .Select(source => sources.TryGetValue(SourceKey(source), out var mapped) ? mapped.SourceId : null)
            .Where(sourceId => sourceId is not null)
            .Cast<string>()
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var identityText = BuildIdentityText(place);
        claims.Add(new EvidenceClaim(
            $"{place.CanonicalId}:identity",
            EvidenceClaimType.Fact,
            identityText,
            placeSourceIds,
            placeSourceIds.Length > 0 ? GroundingVerificationStatus.Verified : GroundingVerificationStatus.Provisional,
            Math.Clamp(place.ConfidenceScore, 0, 1),
            place.LastRefreshedUtc,
            place.LastRefreshedUtc.Add(_evidenceFreshness))
        {
            Category = "place_identity"
        });

        if (place.DistanceFromUserMeters is { } distance)
        {
            claims.Add(new EvidenceClaim(
                $"{place.CanonicalId}:relative-location",
                EvidenceClaimType.Inference,
                $"{place.Name} is {DistancePhrase(distance)} to the {place.DirectionFromUser ?? "nearby"}.",
                placeSourceIds,
                placeSourceIds.Length > 0 ? GroundingVerificationStatus.Verified : GroundingVerificationStatus.Provisional,
                Math.Clamp(place.ConfidenceScore, 0, 1),
                now,
                now.Add(_spatialEvidenceFreshness))
            {
                Category = "relative_location"
            });
        }

        return claims;
    }

    private static IReadOnlyList<GroundedStorySentence> BuildSentenceGrounding(
        LocationStoryResult story,
        LocationPlace? place,
        IReadOnlyList<EvidenceClaim> claims)
    {
        var factIds = story.FactIdsUsed.Where(id => claims.Any(claim => string.Equals(claim.EvidenceId, id, StringComparison.OrdinalIgnoreCase))).ToArray();
        var identityId = place is null ? null : $"{place.CanonicalId}:identity";
        var spatialId = place is null ? null : $"{place.CanonicalId}:relative-location";

        return SplitSentences(story.ShortSpokenNarration)
            .Select((text, index) =>
            {
                var unavailable = IsUnavailableStatement(text);
                var evidenceIds = unavailable
                    ? Array.Empty<string>()
                    : claims.Where(claim =>
                            factIds.Contains(claim.EvidenceId, StringComparer.OrdinalIgnoreCase)
                            || string.Equals(claim.EvidenceId, identityId, StringComparison.OrdinalIgnoreCase)
                            || string.Equals(claim.EvidenceId, spatialId, StringComparison.OrdinalIgnoreCase))
                        .Select(claim => claim.EvidenceId)
                        .Distinct(StringComparer.OrdinalIgnoreCase)
                        .ToArray();
                var contentType = unavailable
                    ? StorySentenceContentType.Unavailable
                    : evidenceIds.Any(id => string.Equals(id, spatialId, StringComparison.OrdinalIgnoreCase))
                        ? StorySentenceContentType.Inference
                        : StorySentenceContentType.Fact;
                return new GroundedStorySentence($"arrival-{index + 1}", text, contentType, evidenceIds, story.Confidence);
            })
            .ToArray();
    }

    private static IReadOnlyList<GroundedStorySection> BuildSections(
        LocationStoryResult story,
        IReadOnlyList<GroundedStorySentence> arrivalSentences,
        IReadOnlyList<EvidenceClaim> claims,
        StoryAudienceProfile profile)
    {
        var supplied = story.StorySections
            .GroupBy(section => section.SectionType)
            .ToDictionary(group => group.Key, group => group.First());
        var orderedFacts = claims
            .Where(claim => claim.ClaimType == EvidenceClaimType.Fact
                && claim.VerificationStatus == GroundingVerificationStatus.Verified
                && !claim.EvidenceId.EndsWith(":identity", StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(claim => ProfileScore(claim, profile))
            .ThenByDescending(claim => claim.Confidence)
            .ThenBy(claim => claim.EvidenceId, StringComparer.Ordinal)
            .ToArray();
        var identity = claims.FirstOrDefault(claim => claim.EvidenceId.EndsWith(":identity", StringComparison.OrdinalIgnoreCase));
        var spatial = claims.FirstOrDefault(claim => claim.EvidenceId.EndsWith(":relative-location", StringComparison.OrdinalIgnoreCase));

        var camera = supplied.TryGetValue(StorySectionType.CameraTeaser, out var suppliedCamera)
            ? DecorateSection(suppliedCamera, 12)
            : ComposeSection(StorySectionType.CameraTeaser, 12, new[] { identity }.Concat(orderedFacts.Take(1)), story.Confidence, false);
        var arrival = supplied.TryGetValue(StorySectionType.Arrival, out var suppliedArrival)
            ? DecorateSection(suppliedArrival, 60)
            : ExtendSection(new GroundedStorySection(StorySectionType.Arrival, arrivalSentences), 60, orderedFacts, story.Confidence);
        if (arrival.Sentences.Count == 0)
        {
            arrival = ComposeSection(StorySectionType.Arrival, 60, new[] { spatial, identity }.Concat(orderedFacts.Take(4)), story.Confidence, false);
        }

        var deeper = supplied.TryGetValue(StorySectionType.Deeper, out var suppliedDeeper)
            ? DecorateSection(suppliedDeeper, 180)
            : ComposeSection(StorySectionType.Deeper, 180, new[] { identity }.Concat(orderedFacts), story.Confidence, orderedFacts.Length < 2);

        return new[] { camera, arrival, deeper };
    }

    private static GroundedStorySection ExtendSection(
        GroundedStorySection section,
        int targetSeconds,
        IReadOnlyList<EvidenceClaim> additionalClaims,
        double confidence)
    {
        var maximumWords = (int)Math.Ceiling(targetSeconds * 2.5);
        var sentences = section.Sentences.ToList();
        var usedEvidence = sentences.SelectMany(sentence => sentence.EvidenceIds).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var words = sentences.Sum(sentence => WordCount(sentence.Text));
        foreach (var claim in additionalClaims.Where(claim => !usedEvidence.Contains(claim.EvidenceId)))
        {
            var claimWords = WordCount(claim.Text);
            if (words + claimWords > maximumWords)
            {
                continue;
            }

            sentences.Add(new GroundedStorySentence(
                $"arrival-{sentences.Count + 1}",
                claim.Text,
                StorySentenceContentType.Fact,
                new[] { claim.EvidenceId },
                Math.Min(confidence, claim.Confidence)));
            usedEvidence.Add(claim.EvidenceId);
            words += claimWords;
        }

        return DecorateSection(section with { Sentences = sentences }, targetSeconds);
    }

    private static GroundedStorySection ComposeSection(
        StorySectionType sectionType,
        int targetSeconds,
        IEnumerable<EvidenceClaim?> candidateClaims,
        double confidence,
        bool appendUnavailable)
    {
        var maximumWords = (int)Math.Ceiling(targetSeconds * 2.5);
        var selected = new List<EvidenceClaim>();
        var wordCount = 0;
        foreach (var claim in candidateClaims.Where(claim => claim is not null).Cast<EvidenceClaim>().DistinctBy(claim => claim.EvidenceId, StringComparer.OrdinalIgnoreCase))
        {
            var claimWords = WordCount(claim.Text);
            if (selected.Count > 0 && wordCount + claimWords > maximumWords)
            {
                continue;
            }

            selected.Add(claim);
            wordCount += claimWords;
        }

        var sentences = selected.Select((claim, index) => new GroundedStorySentence(
            $"{SectionPrefix(sectionType)}-{index + 1}",
            claim.Text,
            claim.ClaimType == EvidenceClaimType.Inference ? StorySentenceContentType.Inference : StorySentenceContentType.Fact,
            new[] { claim.EvidenceId },
            Math.Min(confidence, claim.Confidence))).ToList();
        if (appendUnavailable || sentences.Count == 0)
        {
            sentences.Add(new GroundedStorySentence(
                $"{SectionPrefix(sectionType)}-{sentences.Count + 1}",
                sectionType == StorySectionType.Deeper
                    ? "ROVER could not verify a fuller story for this place yet."
                    : "ROVER could not verify this place yet.",
                StorySentenceContentType.Unavailable,
                Array.Empty<string>(),
                1));
        }

        return DecorateSection(new GroundedStorySection(sectionType, sentences), targetSeconds);
    }

    private static GroundedStorySection DecorateSection(GroundedStorySection section, int targetSeconds)
    {
        var words = section.Sentences.Sum(sentence => WordCount(sentence.Text));
        var estimatedSeconds = words == 0 ? 0 : Math.Max(1, (int)Math.Ceiling(words / 2.5));
        var grounded = section.Sentences.Count(sentence => sentence.ContentType == StorySentenceContentType.Unavailable || sentence.EvidenceIds.Count > 0);
        var evidenceCompleteness = section.Sentences.Count == 0 ? 0 : (double)grounded / section.Sentences.Count;
        var durationCompleteness = targetSeconds == 0 ? 1 : Math.Min(1, (double)estimatedSeconds / targetSeconds);
        var availability = section.Sentences.Any(sentence => sentence.ContentType != StorySentenceContentType.Unavailable)
            ? GroundingVerificationStatus.Verified
            : GroundingVerificationStatus.Unavailable;
        return section with
        {
            TargetDurationSeconds = targetSeconds,
            EstimatedDurationSeconds = estimatedSeconds,
            Completeness = Math.Round(evidenceCompleteness * durationCompleteness, 3),
            Availability = availability
        };
    }

    private static StoryAudienceProfile ResolveProfile(string? narrationStyle, IReadOnlyCollection<string> interests)
    {
        var values = new[] { narrationStyle ?? string.Empty }.Concat(interests).Select(value => value.ToLowerInvariant()).ToArray();
        bool Contains(params string[] terms) => values.Any(value => terms.Any(term => value.Contains(term, StringComparison.Ordinal)));

        if (Contains("accessib", "mobility")) return StoryAudienceProfile.AccessibilityFocused;
        if (Contains("child", "family", "kid")) return StoryAudienceProfile.FamilyWithChildren;
        if (Contains("architect", "design")) return StoryAudienceProfile.ArchitectureEnthusiast;
        if (Contains("history", "historic", "heritage")) return StoryAudienceProfile.HistoryEnthusiast;
        if (Contains("business", "work")) return StoryAudienceProfile.BusinessTraveller;
        if (Contains("outdoor", "nature", "trail", "park")) return StoryAudienceProfile.OutdoorAdventurer;
        if (Contains("local resident", "local")) return StoryAudienceProfile.LocalResident;
        return StoryAudienceProfile.GeneralTraveller;
    }

    private static int ProfileScore(EvidenceClaim claim, StoryAudienceProfile profile)
    {
        var text = $"{claim.Category} {claim.Text}".ToLowerInvariant();
        var terms = profile switch
        {
            StoryAudienceProfile.HistoryEnthusiast => new[] { "history", "historic", "heritage", "founded", "built", "opened" },
            StoryAudienceProfile.ArchitectureEnthusiast => new[] { "architect", "architecture", "building", "design", "style", "constructed" },
            StoryAudienceProfile.FamilyWithChildren => new[] { "family", "child", "children", "museum", "park", "learn" },
            StoryAudienceProfile.BusinessTraveller => new[] { "business", "hotel", "restaurant", "open", "address", "service" },
            StoryAudienceProfile.OutdoorAdventurer => new[] { "outdoor", "park", "trail", "lake", "river", "nature" },
            StoryAudienceProfile.AccessibilityFocused => new[] { "access", "wheelchair", "mobility", "entrance", "elevator" },
            StoryAudienceProfile.LocalResident => new[] { "local", "community", "town", "resident" },
            _ => Array.Empty<string>()
        };
        return terms.Count(term => text.Contains(term, StringComparison.OrdinalIgnoreCase)) * 10;
    }

    private static string? TopicFor(EvidenceClaim claim)
    {
        var value = $"{claim.Category} {claim.Text}".ToLowerInvariant();
        if (ContainsAny(value, "wheelchair", "accessibility", "accessible", "mobility")) return "Accessibility";
        if (ContainsAny(value, "architect", "architecture", "constructed", "building style")) return "Architecture";
        if (ContainsAny(value, "history", "historic", "heritage", "founded", "opened", "built")) return "History";
        if (ContainsAny(value, "film", "movie", "television", "media")) return "Media";
        if (ContainsAny(value, "person", "people", "founder", "architect", "born")) return "People";
        if (ContainsAny(value, "hours", "open", "entrance", "address", "admission")) return "Practical information";
        if (ContainsAny(value, "surprising", "unusual", "notable", "first", "largest", "oldest")) return "Surprising detail";
        return null;
    }

    private static bool ContainsAny(string value, params string[] terms)
        => terms.Any(term => value.Contains(term, StringComparison.OrdinalIgnoreCase));

    private static int WordCount(string value)
        => Regex.Matches(value, @"\b[\p{L}\p{N}']+\b").Count;

    private static string SectionPrefix(StorySectionType sectionType)
        => sectionType switch
        {
            StorySectionType.CameraTeaser => "camera",
            StorySectionType.Arrival => "arrival",
            StorySectionType.Deeper => "deeper",
            _ => "story"
        };

    private static CanonicalPlaceIdentity CreateIdentity(LocationPlace place, DateTimeOffset now)
    {
        string? Find(params string[] keys)
        {
            foreach (var key in keys)
            {
                if (place.ProviderIds.TryGetValue(key, out var value) && !string.IsNullOrWhiteSpace(value))
                {
                    return value;
                }
            }

            return null;
        }

        var knownKeys = new HashSet<string>(new[] { "rover", "gers", "overture", "wikidata", "wikipedia", "google", "googleplaces", "google_places", "osm", "openstreetmap", "mapbox" }, StringComparer.OrdinalIgnoreCase);
        var additional = place.ProviderIds.Where(pair => !knownKeys.Contains(pair.Key))
            .ToDictionary(pair => pair.Key, pair => pair.Value, StringComparer.OrdinalIgnoreCase);
        var identifiers = new PlaceProviderIdentifiers(
            Find("rover"),
            Find("gers", "overture"),
            Find("wikidata"),
            Find("wikipedia"),
            Find("google", "googleplaces", "google_places"),
            Find("osm", "openstreetmap"),
            Find("mapbox"),
            additional);
        var method = place.IdentityResolution?.MatchMethod
            ?? (place.ProviderIds.Count > 0
                ? PlaceIdentityMatchMethod.ExplicitProviderIdentifier
                : PlaceIdentityMatchMethod.Unresolved);

        return new CanonicalPlaceIdentity(
            place.CanonicalId,
            place.Name,
            place.Coordinates.Latitude,
            place.Coordinates.Longitude,
            place.Address,
            place.Categories,
            identifiers,
            method,
            Math.Clamp(place.IdentityResolution?.Confidence ?? place.ConfidenceScore, 0, 1),
            place.IdentityResolution?.ResolvedUtc ?? now);
    }

    private static string BuildIdentityText(LocationPlace place)
    {
        var category = place.Categories.FirstOrDefault();
        if (!string.IsNullOrWhiteSpace(category) && !string.IsNullOrWhiteSpace(place.Address))
        {
            return $"{place.Name} is listed as {category} at {place.Address}.";
        }

        if (!string.IsNullOrWhiteSpace(place.Address))
        {
            return $"{place.Name} is listed at {place.Address}.";
        }

        return string.IsNullOrWhiteSpace(category)
            ? $"{place.Name} is a mapped place."
            : $"{place.Name} is listed as {category}.";
    }

    private static IReadOnlyList<string> SplitSentences(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return Array.Empty<string>();
        }

        return Regex.Split(value.Trim(), @"(?<=[.!?])\s+")
            .Where(sentence => !string.IsNullOrWhiteSpace(sentence))
            .Select(sentence => sentence.Trim())
            .ToArray();
    }

    private static bool IsUnavailableStatement(string text)
        => text.Contains("no verified", StringComparison.OrdinalIgnoreCase)
            || text.Contains("no sourced", StringComparison.OrdinalIgnoreCase)
            || text.Contains("could not verify", StringComparison.OrdinalIgnoreCase)
            || text.Contains("not available", StringComparison.OrdinalIgnoreCase);

    private static string DistancePhrase(double meters)
        => meters < 1000 ? $"{Math.Round(meters)} meters away" : $"{Math.Round(meters / 1000, 1)} kilometers away";

    private static string SourceKey(LocationSource source)
        => $"{source.ProviderName}|{source.ProviderRecordId}|{source.SourceUrl}";

    private static string StableSourceId(LocationSource source)
    {
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(SourceKey(source)))).ToLowerInvariant();
        return $"source:{NormalizeId(source.ProviderName)}:{hash[..16]}";
    }

    private static string NormalizeId(string value)
        => new(value.ToLowerInvariant().Where(char.IsLetterOrDigit).ToArray());
}

public sealed class StrictStoryGroundingValidator : IStoryGroundingValidator
{
    private static readonly HashSet<string> StopWords = new(
        new[] { "the", "and", "that", "this", "with", "from", "your", "you", "has", "have", "for", "but", "are", "was", "were", "near", "nearby", "place", "rover", "away", "listed", "mapped", "basic", "context", "story", "facts", "fact", "yet", "its", "into", "about" },
        StringComparer.OrdinalIgnoreCase);

    public GroundingValidationResult Validate(StoryPack storyPack, DateTimeOffset now)
    {
        var issues = new List<GroundingIssue>();
        var sources = storyPack.Sources.GroupBy(source => source.SourceId, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        var claims = storyPack.EvidenceClaims.GroupBy(claim => claim.EvidenceId, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);

        AddDuplicateIssues(storyPack.Sources.Select(source => source.SourceId), "duplicate_source", issues);
        AddDuplicateIssues(storyPack.EvidenceClaims.Select(claim => claim.EvidenceId), "duplicate_evidence", issues);
        AddDuplicateIssues(storyPack.Sections.SelectMany(section => section.Sentences).Select(sentence => sentence.SentenceId), "duplicate_sentence", issues);

        if (storyPack.SchemaVersion is "1.1" or "2.0")
        {
            foreach (var sectionType in Enum.GetValues<StorySectionType>())
            {
                if (storyPack.Sections.Count(section => section.SectionType == sectionType) != 1)
                {
                    issues.Add(new GroundingIssue("required_section", $"Story Pack {storyPack.SchemaVersion} requires exactly one {sectionType} section.", null, null));
                }
            }

            if (!Enum.TryParse<StoryAudienceProfile>(storyPack.Profile, true, out _))
            {
                issues.Add(new GroundingIssue("unknown_profile", "Story Pack profile is not supported.", null, null));
            }
        }

        if (storyPack.SchemaVersion == "2.0")
        {
            ValidateVersion2Metadata(storyPack, issues);
        }

        foreach (var section in storyPack.Sections)
        {
            var maximumWords = section.SectionType switch
            {
                StorySectionType.CameraTeaser => 45,
                StorySectionType.Arrival => 180,
                StorySectionType.Deeper => 520,
                _ => 520
            };
            if (section.Sentences.Sum(sentence => CountWords(sentence.Text)) > maximumWords)
            {
                issues.Add(new GroundingIssue("section_too_long", $"{section.SectionType} exceeds its narration word limit.", null, null));
            }
        }

        foreach (var claim in storyPack.EvidenceClaims)
        {
            if (claim.ClaimType != EvidenceClaimType.Unavailable && claim.SourceIds.Count == 0)
            {
                issues.Add(new GroundingIssue("evidence_without_source", "Grounded evidence must cite a source.", null, claim.EvidenceId));
            }

            foreach (var sourceId in claim.SourceIds.Where(sourceId => !sources.ContainsKey(sourceId)))
            {
                issues.Add(new GroundingIssue("unknown_source", "Evidence cites an unknown source.", null, claim.EvidenceId));
            }

            if (claim.ExpiresUtc is { } expiresUtc && expiresUtc <= now)
            {
                issues.Add(new GroundingIssue("expired_evidence", "Evidence is outside its freshness window.", null, claim.EvidenceId));
            }
        }

        foreach (var sentence in storyPack.Sections.SelectMany(section => section.Sentences))
        {
            if (sentence.ContentType == StorySentenceContentType.Unavailable && !IsUnavailableSentence(sentence.Text))
            {
                issues.Add(new GroundingIssue("mislabeled_unavailable", "Unavailable content must explicitly state that information is unavailable or unverified.", sentence.SentenceId, null));
                continue;
            }

            if (sentence.ContentType != StorySentenceContentType.Unavailable && sentence.EvidenceIds.Count == 0)
            {
                issues.Add(new GroundingIssue("uncited_sentence", "Every factual or inferred sentence must cite evidence.", sentence.SentenceId, null));
                continue;
            }

            var citedClaims = sentence.EvidenceIds.Where(claims.ContainsKey).Select(id => claims[id]).ToArray();
            foreach (var evidenceId in sentence.EvidenceIds.Where(id => !claims.ContainsKey(id)))
            {
                issues.Add(new GroundingIssue("unknown_evidence", "Sentence cites unknown evidence.", sentence.SentenceId, evidenceId));
            }

            if (sentence.ContentType == StorySentenceContentType.Fact
                && !citedClaims.Any(claim => claim.VerificationStatus == GroundingVerificationStatus.Verified))
            {
                issues.Add(new GroundingIssue("unverified_fact", "A factual sentence must cite verified evidence.", sentence.SentenceId, null));
            }

            if (sentence.ContentType != StorySentenceContentType.Unavailable
                && citedClaims.Length > 0
                && !IsLexicallySupported(sentence.Text, citedClaims))
            {
                issues.Add(new GroundingIssue("unsupported_sentence", "Sentence text is not supported by its cited evidence.", sentence.SentenceId, null));
            }
        }

        var status = issues.Count == 0
            ? GroundingVerificationStatus.Verified
            : GroundingVerificationStatus.Rejected;
        return new GroundingValidationResult(issues.Count == 0, status, now, issues);
    }

    private static void ValidateVersion2Metadata(StoryPack storyPack, ICollection<GroundingIssue> issues)
    {
        if (string.IsNullOrWhiteSpace(storyPack.StoryId))
        {
            issues.Add(new GroundingIssue("missing_story_id", "Story Pack 2.0 requires a stable story identifier.", null, null));
        }

        if (string.IsNullOrWhiteSpace(storyPack.EntityId)
            || storyPack.PlaceIdentity is null
            || !string.Equals(storyPack.EntityId, storyPack.PlaceIdentity.CanonicalPlaceId, StringComparison.OrdinalIgnoreCase))
        {
            issues.Add(new GroundingIssue("invalid_entity_id", "Story Pack 2.0 entity identity must match its canonical place.", null, null));
        }

        if (storyPack.GeographicAnchor is null)
        {
            issues.Add(new GroundingIssue("missing_geographic_anchor", "Story Pack 2.0 requires a geographic anchor.", null, null));
        }

        if (storyPack.PrimaryCategory is null || storyPack.Categories.Count == 0)
        {
            issues.Add(new GroundingIssue("missing_story_category", "Story Pack 2.0 requires at least one supported story category.", null, null));
        }

        if (storyPack.EvidenceQualityScore is null or < 0 or > 1
            || storyPack.FreshnessClassification is null
            || storyPack.RetrievedUtc is null
            || storyPack.CacheEligibility is null
            || storyPack.InteractionState is null)
        {
            issues.Add(new GroundingIssue("incomplete_story_metadata", "Story Pack 2.0 quality, freshness, cache, retrieval, and narration metadata is required.", null, null));
        }

        AddDuplicateIssues(storyPack.NarrationVariants.Select(variant => variant.VariantId), "duplicate_variant", issues);
        var sentenceIds = storyPack.Sections.SelectMany(section => section.Sentences)
            .Select(sentence => sentence.SentenceId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var evidenceIds = storyPack.EvidenceClaims.Select(claim => claim.EvidenceId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var variantType in Enum.GetValues<StoryNarrationVariantType>())
        {
            if (storyPack.NarrationVariants.Count(variant => variant.VariantType == variantType) != 1)
            {
                issues.Add(new GroundingIssue("required_variant", $"Story Pack 2.0 requires exactly one {variantType} narration variant.", null, null));
            }
        }

        foreach (var variant in storyPack.NarrationVariants)
        {
            if (variant.TargetDurationSeconds <= 0 || variant.EstimatedDurationSeconds < 0)
            {
                issues.Add(new GroundingIssue("invalid_variant_duration", "Narration variant durations must be bounded non-negative values.", null, null));
            }

            foreach (var missingSentence in variant.SentenceIds.Where(id => !sentenceIds.Contains(id)))
            {
                issues.Add(new GroundingIssue("unknown_variant_sentence", "Narration variant references an unknown sentence.", missingSentence, null));
            }

            foreach (var missingEvidence in variant.EvidenceIds.Where(id => !evidenceIds.Contains(id)))
            {
                issues.Add(new GroundingIssue("unknown_variant_evidence", "Narration variant references unknown evidence.", null, missingEvidence));
            }
        }
    }

    private static bool IsLexicallySupported(string sentence, IReadOnlyList<EvidenceClaim> claims)
    {
        var sentenceTokens = MeaningfulTokens(sentence);
        if (sentenceTokens.Count == 0)
        {
            return true;
        }

        var claimTokens = claims.SelectMany(claim => MeaningfulTokens(claim.Text)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var sentenceNumbers = sentenceTokens.Where(token => token.All(char.IsDigit)).ToArray();
        if (sentenceNumbers.Any(number => !claimTokens.Contains(number)))
        {
            return false;
        }

        var matched = sentenceTokens.Count(claimTokens.Contains);
        return (double)matched / sentenceTokens.Count >= 0.45;
    }

    private static IReadOnlyList<string> MeaningfulTokens(string value)
        => Regex.Matches(value.ToLowerInvariant(), @"[a-z0-9]+")
            .Select(match => match.Value)
            .Where(token => (token.Length >= 3 || token.All(char.IsDigit)) && !StopWords.Contains(token))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

    private static void AddDuplicateIssues(IEnumerable<string> ids, string code, ICollection<GroundingIssue> issues)
    {
        foreach (var duplicate in ids.GroupBy(id => id, StringComparer.OrdinalIgnoreCase).Where(group => group.Count() > 1))
        {
            issues.Add(new GroundingIssue(code, "Identifiers must be unique within a Story Pack.", null, duplicate.Key));
        }
    }

    private static int CountWords(string value)
        => Regex.Matches(value, @"\b[\p{L}\p{N}']+\b").Count;

    private static bool IsUnavailableSentence(string value)
        => value.Contains("could not verify", StringComparison.OrdinalIgnoreCase)
            || value.Contains("not available", StringComparison.OrdinalIgnoreCase)
            || value.Contains("unavailable", StringComparison.OrdinalIgnoreCase)
            || value.Contains("no verified", StringComparison.OrdinalIgnoreCase)
            || value.Contains("no sourced", StringComparison.OrdinalIgnoreCase)
            || value.Contains("not yet verified", StringComparison.OrdinalIgnoreCase)
            || value.Contains("insufficient evidence", StringComparison.OrdinalIgnoreCase);
}
