using Rover.Api.Contracts;
using Rover.Application.Conversation;
using Rover.Application.Walks;
using Rover.Domain.Profiles;
using Rover.Domain.Walks;

namespace Rover.Api.Mapping;

public static class WalkResponseMapper
{
    public static WalkSessionResponse ToResponse(this WalkSession session)
    {
        var stops = session.Stops.Select(ToResponse).ToList();
        var routeQuality = new DeterministicRouteQualityAnalyzer().Analyze(session);
        var lifecycleConsistency = new StopLifecycleConsistencyService().Inspect(session);
        var recentNarration = session.RecentNarrationStopId is null
            ? null
            : session.Stops.FirstOrDefault(stop => stop.StopId == session.RecentNarrationStopId)?.ToResponse();

        return new WalkSessionResponse(
            session.WalkSessionId,
            session.Status.ToString(),
            session.StartingLocation.ToResponse(),
            session.LastKnownLocation?.ToResponse(),
            session.CreatedAtUtc,
            session.StartedAtUtc,
            session.CompletedAtUtc,
            session.CancelledAtUtc,
            session.AvailableMinutes,
            session.EstimatedDurationMinutes,
            session.EstimatedDistanceMeters,
            session.RouteSummary,
            session.Interests,
            session.WalkingPace.ToString(),
            session.AccessibilityPreferences.Select(preference => preference.ToString()).ToArray(),
            session.TimeRemainingMinutes,
            session.VisitedStopCount,
            session.ProgressPercentage,
            session.NextStop?.ToResponse(),
            session.RecentNarrationStopId,
            recentNarration,
            session.Route.ToResponse(),
            session.OriginalRoute.ToResponse(),
            session.RouteRevision,
            session.RouteRevisions.Select(revision => revision.ToResponse()).ToArray(),
            session.TrackingState.DistanceToNextStopMeters,
            session.TrackingState.RouteProgressPercentage,
            session.TrackingState.IsOffRoute,
            session.TrackingState.DistanceFromRouteMeters,
            routeQuality.ToResponse(),
            lifecycleConsistency.ToResponse(),
            stops);
    }

    public static LocationUpdateResponse ToResponse(this LocationUpdateResult result)
    {
        return new LocationUpdateResponse(
            result.WalkSessionId,
            result.Status.ToString(),
            result.Accepted,
            result.NextStop?.ToResponse(),
            result.DistanceToNextStopMeters,
            result.RouteProgressPercentage,
            result.EstimatedMinutesRemaining,
            result.IsOffRoute,
            result.DistanceFromRouteMeters,
            result.ArrivalCandidate,
            result.ArrivalCandidateReadingCount,
            result.ArrivalCandidateStopId,
            result.ConfirmedArrival?.ToResponse(),
            result.ServerTimestampUtc);
    }

    public static AskRoverResponse ToResponse(this AskRoverResult result)
    {
        return new AskRoverResponse(
            result.ConversationId,
            result.TurnId,
            result.AnswerText,
            result.CreatedAtUtc,
            result.CurrentStopId,
            result.Provider,
            result.SuggestedAction,
            result.SafetyNotice);
    }

    public static ProfileResponse ToResponse(this GuestProfile profile)
    {
        return new ProfileResponse(
            profile.ProfileId,
            profile.InstallationId,
            profile.CreatedAtUtc,
            profile.UpdatedAtUtc,
            profile.Preferences.ToResponse(),
            profile.SavedDiscoveries.Select(item => new SavedDiscoveryResponse(
                item.SavedDiscoveryId,
                item.DiscoveryId,
                item.Name,
                item.Category,
                item.SavedAtUtc,
                item.Source)).ToArray(),
            profile.LearnedPreferences.Select(item => new LearnedPreferenceResponse(
                item.Topic,
                item.Score,
                item.Reason,
                item.UpdatedAtUtc)).ToArray(),
            profile.Version)
        {
            StoryInteractionCount = profile.StoryInteractions.Count
        };
    }

    private static UserPreferencesResponse ToResponse(this UserPreferences preferences)
    {
        return new UserPreferencesResponse(
            preferences.Interests,
            preferences.WalkingPace,
            preferences.AccessibilityNeeds,
            preferences.DistanceUnits,
            preferences.DirectionVoiceEnabled,
            preferences.NarrationEnabled,
            preferences.SpeechRate,
            preferences.PreferredNarrationLength,
            preferences.PremiumVoiceEnabled,
            preferences.AskRoverVoiceEnabled,
            preferences.AutoPlayNarrationOnArrival,
            preferences.ResumeNarrationAfterNavigation,
            preferences.DeviceVoiceFallbackEnabled,
            preferences.SaveWalkHistory,
            preferences.ImproveRecommendations,
            preferences.LocationRetention)
        {
            StoryDensity = preferences.StoryDensity,
            ExcludedStoryCategories = preferences.ExcludedStoryCategories
        };
    }

    public static WalkAdaptationResponse ToResponse(this WalkAdaptationProposal proposal)
    {
        return new WalkAdaptationResponse(
            proposal.AdaptationId,
            proposal.WalkSessionId,
            proposal.Type.ToString(),
            proposal.Title,
            proposal.Explanation,
            proposal.EstimatedAddedMinutes,
            proposal.EstimatedAddedDistanceMeters,
            proposal.EstimatedNewTotalMinutes,
            proposal.AffectedStops,
            proposal.AddedStops,
            proposal.RemovedStops,
            proposal.ReorderedStops,
            proposal.ProposedRoute.ToResponse(),
            proposal.ProposedStops.Select(stop => stop.ToResponse()).ToArray(),
            proposal.RouteRevision,
            proposal.ProposedRouteRevision,
            proposal.CreatedAtUtc,
            proposal.ExpiresAtUtc,
            proposal.Status.ToString());
    }

    public static WalkStopResponse ToResponse(this WalkStop stop)
    {
        return new WalkStopResponse(
            stop.StopId,
            stop.SequenceNumber,
            stop.Name,
            stop.Location.Latitude,
            stop.Location.Longitude,
            stop.ShortDescription,
            stop.Narration,
            stop.Category,
            stop.ContentType.ToString(),
            stop.ContentSource.ToString(),
            stop.SponsoredDisclosure,
            stop.Address,
            stop.WebsiteUrl,
            stop.PhoneNumber,
            stop.MenuUrl,
            stop.EstimatedVisitMinutes,
            stop.DistanceFromPreviousStopMeters,
            stop.ArrivalRadiusMeters,
            stop.Visited,
            stop.ArrivalState.ToString(),
            stop.ArrivedAtUtc,
            stop.DiscoveryProviderName,
            stop.ProviderPlaceId,
            stop.SourceUrl,
            stop.RequiredAttribution);
    }

    private static LocationResponse ToResponse(this GeoLocation location)
    {
        return new LocationResponse(location.Latitude, location.Longitude);
    }

    private static WalkRouteRevisionResponse ToResponse(this WalkRouteRevision revision)
    {
        return new WalkRouteRevisionResponse(
            revision.Revision,
            revision.Reason,
            revision.AppliedAtUtc,
            revision.AddedStopIds,
            revision.RemovedStopIds,
            revision.ReorderedStopIds);
    }

    private static RouteQualityDiagnosticsResponse ToResponse(this RouteQualityDiagnostics diagnostics)
    {
        return new RouteQualityDiagnosticsResponse(
            diagnostics.TotalRouteDistanceMeters,
            diagnostics.EstimatedWalkingTimeMinutes,
            diagnostics.EstimatedStopTimeMinutes,
            diagnostics.EstimatedExperienceTimeMinutes,
            diagnostics.AvailableTimeUtilization,
            diagnostics.BacktrackingEstimateMeters,
            diagnostics.RepeatedSegmentCount,
            diagnostics.ReturnToStartEstimateMeters,
            diagnostics.Warnings);
    }

    private static StopLifecycleConsistencyResponse ToResponse(this StopLifecycleConsistencyReport report)
    {
        return new StopLifecycleConsistencyResponse(
            report.IsConsistent,
            report.StopCount,
            report.RouteRevision,
            report.NextStopId,
            report.Warnings);
    }

    private static WalkRouteResponse ToResponse(this WalkRoute route)
    {
        var coordinates = route.Coordinates
            .Select(point => new RouteCoordinateResponse(point.Longitude, point.Latitude))
            .ToArray();

        return new WalkRouteResponse(
            route.RouteId,
            route.Provider,
            route.Version,
            route.GeneratedAtUtc,
            coordinates,
            new
            {
                type = "LineString",
                coordinates = coordinates.Select(point => new[] { point.Longitude, point.Latitude }).ToArray()
            },
            new RouteBoundsResponse(
                new RouteCoordinateResponse(route.Bounds.Southwest.Longitude, route.Bounds.Southwest.Latitude),
                new RouteCoordinateResponse(route.Bounds.Northeast.Longitude, route.Bounds.Northeast.Latitude)),
            route.DistanceMeters,
            route.DurationMinutes,
            route.Maneuvers.Select(maneuver => new WalkRouteManeuverResponse(
                maneuver.SequenceNumber,
                maneuver.Instruction,
                maneuver.DistanceMeters,
                maneuver.DurationMinutes,
                maneuver.ManeuverType,
                maneuver.Location is null
                    ? null
                    : new RouteCoordinateResponse(maneuver.Location.Longitude, maneuver.Location.Latitude))).ToArray());
    }
}
