namespace Rover.Api.Contracts;

public sealed record CreateWalkRequest(
    double? Latitude,
    double? Longitude,
    int? AvailableMinutes,
    IReadOnlyCollection<string>? Interests,
    string? WalkingPace,
    IReadOnlyCollection<string>? AccessibilityPreferences);
