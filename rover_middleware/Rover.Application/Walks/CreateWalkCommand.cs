using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public sealed record CreateWalkCommand(
    GeoLocation StartingLocation,
    int AvailableMinutes,
    IReadOnlyCollection<string> Interests,
    WalkingPace WalkingPace,
    IReadOnlyCollection<AccessibilityPreference> AccessibilityPreferences)
{
    public string NaturalRequest { get; init; } = "";
    public string Companions { get; init; } = "Solo";
    public string RouteShape { get; init; } = "Loop route";
    public string Environment { get; init; } = "Either";
    public bool IncludePaidAttractions { get; init; }
    public bool SurpriseMe { get; init; }
}
