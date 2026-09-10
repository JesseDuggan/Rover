namespace Rover.Application.Journeys;

public enum NarrativeScheduleAction
{
    Narrate,
    Silence,
    Interrupt,
    Resume,
    Discard
}

public sealed record NarrativeScheduleResult(
    NarrativeScheduleAction Action,
    string Reason);

public interface INarrativeScheduler
{
    NarrativeScheduleResult Evaluate(JourneyNarrationQuery query, double? evidenceStrength = null);
}

public sealed class DeterministicNarrativeScheduler : INarrativeScheduler
{
    private readonly Phase15Options _options;

    public DeterministicNarrativeScheduler(Phase15Options options)
    {
        _options = options;
    }

    public NarrativeScheduleResult Evaluate(JourneyNarrationQuery query, double? evidenceStrength = null)
    {
        if (!_options.Enabled || !_options.NarrativeSchedulerEnabled)
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Narrate, "Phase 15 scheduler is disabled; legacy narration policy applies.");
        }

        var interruptedStory = !string.IsNullOrWhiteSpace(query.InterruptedStoryId);
        if (interruptedStory &&
            (query.InterruptedStoryExpiresUtc is { } expiresUtc && expiresUtc <= query.RequestedAtUtc
             || !query.InterruptedStoryStillRelevant
             || !string.Equals(query.InterruptedStoryRouteId, query.RouteId, StringComparison.OrdinalIgnoreCase)))
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Discard, "The interrupted story is stale or no longer relevant to this route.");
        }

        if (!string.Equals(query.RouteState, "onRoute", StringComparison.OrdinalIgnoreCase))
        {
            return new NarrativeScheduleResult(interruptedStory ? NarrativeScheduleAction.Interrupt : NarrativeScheduleAction.Silence, "Route guidance is not stable enough for optional storytelling.");
        }

        if (query.SecondsUntilNextManeuver is { } seconds && seconds <= _options.UrgentManeuverWindowSeconds)
        {
            return new NarrativeScheduleResult(interruptedStory ? NarrativeScheduleAction.Interrupt : NarrativeScheduleAction.Silence, "A navigation instruction is imminent.");
        }

        if (!query.UserAttentionAvailable || query.RecentDirectInteraction)
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Silence, "The user is occupied or recently interacted with Rover.");
        }

        if (query.AudioAlreadyQueued)
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Silence, "Another audio item already owns the playback queue.");
        }

        if (query.SpeedMetersPerSecond is > 3.5)
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Silence, "Travel speed is outside the supported walking narration range.");
        }

        if (!query.ConnectivityAvailable && !interruptedStory)
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Silence, "Connectivity is unavailable for a new story lookup.");
        }

        if (query.BatterySaverEnabled || IsThermallyConstrained(query.ThermalState))
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Silence, "Device power or thermal pressure suppresses optional storytelling.");
        }

        if (string.Equals(query.StoryDensity, "quiet", StringComparison.OrdinalIgnoreCase))
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Silence, "Story density is set to Quiet.");
        }

        if (evidenceStrength.HasValue
            && string.Equals(query.StoryDensity, "highlights", StringComparison.OrdinalIgnoreCase)
            && evidenceStrength.Value < 0.8)
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Silence, "This story does not meet Highlights evidence strength.");
        }

        if (query.SecondsUntilNextManeuver is { } timeToManeuver
            && query.StoryDurationSeconds is { } storyDuration
            && timeToManeuver < storyDuration + _options.StoryNavigationBufferSeconds)
        {
            return new NarrativeScheduleResult(NarrativeScheduleAction.Silence, "The story does not fit before the next navigation instruction.");
        }

        return new NarrativeScheduleResult(
            interruptedStory ? NarrativeScheduleAction.Resume : NarrativeScheduleAction.Narrate,
            interruptedStory ? "The same story remains fresh, relevant, and clear of navigation." : "A grounded story fits the current journey window.");
    }

    private static bool IsThermallyConstrained(string? thermalState) =>
        thermalState is not null
        && (thermalState.Equals("serious", StringComparison.OrdinalIgnoreCase)
            || thermalState.Equals("critical", StringComparison.OrdinalIgnoreCase));
}
