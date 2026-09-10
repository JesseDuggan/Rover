using Rover.Domain.Walks;

namespace Rover.Application.Conversation;

public sealed record RoverConversationContext(
    string WalkSessionId,
    WalkSessionStatus Status,
    GeoLocation? CurrentLocation,
    WalkStop? CurrentStop,
    WalkStop? NextStop,
    string RouteSummary,
    int EstimatedMinutesRemaining,
    IReadOnlyCollection<string> Interests,
    WalkingPace WalkingPace,
    IReadOnlyCollection<AccessibilityPreference> AccessibilityPreferences,
    IReadOnlyList<WalkStop> VisitedStops,
    IReadOnlyList<WalkStop> RemainingStops,
    string CurrentStopNarration,
    IReadOnlyList<ConversationTurn> RecentTurns);
