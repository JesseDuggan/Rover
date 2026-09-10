using Rover.Api.Contracts;
using Rover.Application.Journeys;
using Rover.Application.LocationIntelligence;
using Rover.Domain.Walks;

namespace Rover.Api.Mapping;

public static class LocationIntelligenceResponseMapper
{
    public static LocationStoryContextResponse ToResponse(this LocationStoryContext context)
    {
        return new LocationStoryContextResponse(
            context.UserCoordinates.ToResponse(),
            context.SearchRadiusMeters,
            context.RouteOrWalkId,
            context.ProfileId,
            context.GeneratedUtc,
            context.RankedPlaces.Select(ToResponse).ToArray(),
            context.WeatherTimeContext?.ToResponse(),
            context.SourceWarnings,
            context.ProviderStatus.Select(ToResponse).ToArray(),
            context.CacheStatus.ToResponse());
    }

    public static LocationStoryResponse ToResponse(this LocationStoryResult story)
    {
        return new LocationStoryResponse(
            story.StoryTitle,
            story.ShortSpokenNarration,
            story.TellMeMore,
            story.PlaceId,
            story.FactIdsUsed,
            story.SourceReferences.Select(ToResponse).ToArray(),
            story.Confidence,
            story.RequiredAttribution,
            story.Warnings)
        {
            StoryPack = story.StoryPack?.ToResponse()
        };
    }

    public static JourneyNarrationDecisionResponse ToResponse(this JourneyNarrationDecision decision)
    {
        return new JourneyNarrationDecisionResponse(
            decision.ShouldNarrate,
            decision.Kind.ToString(),
            decision.Priority.ToString(),
            decision.NarrationText,
            decision.PlaceId,
            decision.FactIdsUsed,
            decision.SourceReferences.Select(ToResponse).ToArray(),
            decision.CooldownSeconds,
            decision.Warnings)
        {
            SchedulerApplied = decision.SchedulerApplied,
            ScheduleAction = decision.ScheduleAction.ToString(),
            ScheduleReason = decision.ScheduleReason,
            StoryId = decision.StoryId,
            StoryExpiresUtc = decision.StoryExpiresUtc,
            EstimatedDurationSeconds = decision.EstimatedDurationSeconds,
            RankingScore = decision.RankingScore,
            RankingReasons = decision.RankingReasons,
            AudioCacheEligible = decision.AudioCacheEligible,
            RetentionClass = decision.RetentionClass
        };
    }

    public static LocationPlaceResponse ToResponse(this LocationPlace place)
    {
        return new LocationPlaceResponse(
            place.CanonicalId,
            place.Name,
            place.Coordinates.ToResponse(),
            place.Address,
            place.Categories,
            place.ShortDescription,
            place.Facts.Select(ToResponse).ToArray(),
            place.SourceReferences.Select(ToResponse).ToArray(),
            place.ProviderIds,
            place.DistanceFromUserMeters,
            place.DistanceFromRouteMeters,
            place.EstimatedDetourMinutes,
            place.DirectionFromUser,
            place.ConfidenceScore,
            place.StoryWorthinessScore,
            place.StoryWorthinessReasons,
            place.ImageReferences.Select(ToResponse).ToArray(),
            place.OpeningStatus,
            place.AccessibilityInformation,
            place.LastRefreshedUtc)
        {
            IdentityResolution = place.IdentityResolution is null
                ? null
                : new PlaceIdentityResolutionResponse(
                    place.IdentityResolution.MatchMethod.ToString(),
                    place.IdentityResolution.VerificationStatus.ToString(),
                    place.IdentityResolution.Confidence,
                    place.IdentityResolution.Candidates.Select(candidate => new PlaceIdentityCandidateResponse(
                        candidate.ProviderName,
                        candidate.ProviderRecordId,
                        candidate.WikidataQid,
                        candidate.Confidence)).ToArray(),
                    place.IdentityResolution.ResolvedUtc)
        };
    }

    private static LocationFactResponse ToResponse(LocationFact fact)
    {
        return new LocationFactResponse(
            fact.FactId,
            fact.FactType,
            fact.FactText,
            fact.Source.ToResponse(),
            fact.ConfidenceScore,
            fact.IsSuitableForNarration,
            fact.RetrievedUtc);
    }

    private static LocationSourceResponse ToResponse(this LocationSource source)
    {
        return new LocationSourceResponse(
            source.ProviderName,
            source.ProviderRecordId,
            source.SourceUrl,
            source.Attribution,
            source.License,
            source.RetrievedUtc,
            source.ConfidenceScore)
        {
            SourceTitle = source.SourceTitle,
            ExpiresUtc = source.ExpiresUtc
        };
    }

    private static StoryPackResponse ToResponse(this StoryPack storyPack)
        => new(
            storyPack.SchemaVersion,
            storyPack.PlaceIdentity?.ToResponse(),
            storyPack.Profile,
            storyPack.Sections.Select(section => new GroundedStorySectionResponse(
                section.SectionType.ToString(),
                section.Sentences.Select(sentence => new GroundedStorySentenceResponse(
                    sentence.SentenceId,
                    sentence.Text,
                    sentence.ContentType.ToString(),
                    sentence.EvidenceIds,
                    sentence.Confidence)).ToArray())
            {
                TargetDurationSeconds = section.TargetDurationSeconds,
                EstimatedDurationSeconds = section.EstimatedDurationSeconds,
                Completeness = section.Completeness,
                Availability = section.Availability.ToString()
            }).ToArray(),
            storyPack.EvidenceClaims.Select(claim => new EvidenceClaimResponse(
                claim.EvidenceId,
                claim.ClaimType.ToString(),
                claim.Text,
                claim.SourceIds,
                claim.VerificationStatus.ToString(),
                claim.Confidence,
                claim.RetrievedUtc,
                claim.ExpiresUtc)
            {
                Category = claim.Category
            }).ToArray(),
            storyPack.Sources.Select(source => new EvidenceSourceReferenceResponse(
                source.SourceId,
                source.ProviderName,
                source.ProviderRecordId,
                source.SourceTitle,
                source.SourceUrl,
                source.Attribution,
                source.License,
                source.RetrievedUtc,
                source.ExpiresUtc,
                source.Confidence)).ToArray(),
            storyPack.Confidence,
            storyPack.Completeness,
            storyPack.RequiredAttribution,
            storyPack.GeneratedUtc,
            storyPack.ExpiresUtc,
            storyPack.Validation is null
                ? null
                : new GroundingValidationResponse(
                    storyPack.Validation.IsValid,
                    storyPack.Validation.Status.ToString(),
                    storyPack.Validation.ValidatedUtc,
                    storyPack.Validation.Issues.Select(issue => new GroundingIssueResponse(
                        issue.Code,
                        issue.Message,
                        issue.SentenceId,
                        issue.EvidenceId)).ToArray()))
        {
            LastVerifiedUtc = storyPack.LastVerifiedUtc,
            AvailableTopics = storyPack.AvailableTopics,
            UnavailableTopics = storyPack.UnavailableTopics,
            StoryId = storyPack.StoryId,
            EntityId = storyPack.EntityId,
            GeographicAnchor = storyPack.GeographicAnchor is null
                ? null
                : new StoryGeographicAnchorResponse(
                    storyPack.GeographicAnchor.Latitude,
                    storyPack.GeographicAnchor.Longitude,
                    storyPack.GeographicAnchor.RouteId,
                    storyPack.GeographicAnchor.RouteSegmentId,
                    storyPack.GeographicAnchor.DirectionalContext),
            PrimaryCategory = storyPack.PrimaryCategory?.ToString(),
            Categories = storyPack.Categories.Select(category => category.ToString()).ToArray(),
            InterestTags = storyPack.InterestTags,
            NarrationVariants = storyPack.NarrationVariants.Select(variant => new StoryNarrationVariantResponse(
                variant.VariantId,
                variant.VariantType.ToString(),
                variant.SectionType.ToString(),
                variant.TargetDurationSeconds,
                variant.EstimatedDurationSeconds,
                variant.SentenceIds,
                variant.EvidenceIds,
                variant.PrefetchedAudioReference)).ToArray(),
            EvidenceQualityScore = storyPack.EvidenceQualityScore,
            FreshnessClassification = storyPack.FreshnessClassification?.ToString(),
            RetrievedUtc = storyPack.RetrievedUtc,
            CacheEligibility = storyPack.CacheEligibility is null
                ? null
                : new StoryCacheEligibilityResponse(
                    storyPack.CacheEligibility.OfflineEligible,
                    storyPack.CacheEligibility.AudioCacheEligible,
                    storyPack.CacheEligibility.RetentionClass,
                    storyPack.CacheEligibility.Reason),
            InteractionState = storyPack.InteractionState is null
                ? null
                : new StoryInteractionStateResponse(
                    storyPack.InteractionState.NarrationStatus.ToString(),
                    storyPack.InteractionState.PreviouslyHeard,
                    storyPack.InteractionState.Completed,
                    storyPack.InteractionState.Skipped,
                    storyPack.InteractionState.Dismissed),
            FollowUpPrompts = storyPack.FollowUpPrompts,
            RelatedStoryPackIds = storyPack.RelatedStoryPackIds
        };

    private static CanonicalPlaceIdentityResponse ToResponse(this CanonicalPlaceIdentity identity)
        => new(
            identity.CanonicalPlaceId,
            identity.Name,
            identity.Latitude,
            identity.Longitude,
            identity.Address,
            identity.Categories,
            new PlaceProviderIdentifiersResponse(
                identity.ProviderIdentifiers.RoverId,
                identity.ProviderIdentifiers.GersId,
                identity.ProviderIdentifiers.WikidataQid,
                identity.ProviderIdentifiers.WikipediaPageId,
                identity.ProviderIdentifiers.GooglePlaceId,
                identity.ProviderIdentifiers.OpenStreetMapId,
                identity.ProviderIdentifiers.MapboxId,
                identity.ProviderIdentifiers.AdditionalIds),
            identity.MatchMethod.ToString(),
            identity.Confidence,
            identity.VerifiedUtc);

    private static LocationImageReferenceResponse ToResponse(LocationImageReference image)
        => new(image.Url, image.Caption, image.Source.ToResponse());

    private static WeatherTimeContextResponse ToResponse(this WeatherTimeContext weather)
        => new(weather.Summary, weather.Temperature, weather.Conditions, weather.ObservedUtc, weather.Source?.ToResponse());

    private static LocationProviderStatusResponse ToResponse(LocationProviderStatus status)
        => new(status.ProviderName, status.Enabled, status.Succeeded, status.CacheHit, status.ResultCount, status.LatencyMilliseconds, status.Warning);

    private static LocationCacheStatusResponse ToResponse(this LocationCacheStatus status)
        => new(status.CacheKey, status.Hit, status.ExpiresUtc);

    private static LocationResponse ToResponse(this GeoLocation location)
        => new(location.Latitude, location.Longitude);
}
