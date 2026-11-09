using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public sealed record CreateWalkCommand(
    GeoLocation StartingLocation,
    int AvailableMinutes,
    IReadOnlyCollection<string> Interests,
    WalkingPace WalkingPace,
    IReadOnlyCollection<AccessibilityPreference> AccessibilityPreferences)
{
    public Action<WalkStop, string>? RecordLabDecision { get; init; }
    public double WalkingSecondsAtPace(double seconds) => LimitLabDetours ? WalkingPace switch
    {
        WalkingPace.Leisurely => seconds * 1.35,
        WalkingPace.Brisk => seconds * (1.35 / 1.7),
        _ => seconds
    } : seconds;
    public bool LimitLabDetours { get; init; }
    public GeoLocation? StoryDestination { get; init; }
    public Guid? ProfileId { get; init; }
    public string NaturalRequest { get; init; } = "";
    public string Companions { get; init; } = "Solo";
    public string RouteShape { get; init; } = "Loop route";
    public string Environment { get; init; } = "Either";
    public bool IncludePaidAttractions { get; init; }
    public bool SurpriseMe { get; init; }
    public WalkPlaceSelection? SelectedPlace { get; init; }
}
