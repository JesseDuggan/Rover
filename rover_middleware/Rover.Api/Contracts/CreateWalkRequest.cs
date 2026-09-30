namespace Rover.Api.Contracts;

public sealed record CreateWalkRequest(
    double? Latitude,
    double? Longitude,
    int? AvailableMinutes,
    IReadOnlyCollection<string>? Interests,
    string? WalkingPace,
    IReadOnlyCollection<string>? AccessibilityPreferences)
{
    public string NaturalRequest { get; init; } = "";
    public string Companions { get; init; } = "Solo";
    public string RouteShape { get; init; } = "Loop route";
    public string Environment { get; init; } = "Either";
    public bool IncludePaidAttractions { get; init; }
    public bool SurpriseMe { get; init; }
}
