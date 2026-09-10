namespace Rover.Api.Contracts;

public sealed record WalkRouteRevisionResponse(
    int Revision,
    string Reason,
    DateTimeOffset AppliedAtUtc,
    IReadOnlyList<string> AddedStopIds,
    IReadOnlyList<string> RemovedStopIds,
    IReadOnlyList<string> ReorderedStopIds);
