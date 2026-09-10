namespace Rover.Domain.Walks;

public sealed record WalkRouteRevision(
    int Revision,
    string Reason,
    DateTimeOffset AppliedAtUtc,
    IReadOnlyList<string> AddedStopIds,
    IReadOnlyList<string> RemovedStopIds,
    IReadOnlyList<string> ReorderedStopIds);
