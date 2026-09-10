using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public sealed record CreateWalkCommand(
    GeoLocation StartingLocation,
    int AvailableMinutes,
    IReadOnlyCollection<string> Interests,
    WalkingPace WalkingPace,
    IReadOnlyCollection<AccessibilityPreference> AccessibilityPreferences);
