namespace Rover.Domain.Walks;

public sealed class WalkAdaptationProposal
{
    public WalkAdaptationProposal(
        string adaptationId,
        string walkSessionId,
        WalkAdaptationType type,
        string title,
        string explanation,
        int estimatedAddedMinutes,
        int estimatedAddedDistanceMeters,
        int estimatedNewTotalMinutes,
        IReadOnlyList<string> affectedStops,
        IReadOnlyList<string> addedStops,
        IReadOnlyList<string> removedStops,
        IReadOnlyList<string> reorderedStops,
        WalkRoute proposedRoute,
        IReadOnlyList<WalkStop> proposedStops,
        int routeRevision,
        DateTimeOffset createdAtUtc,
        DateTimeOffset expiresAtUtc)
    {
        AdaptationId = adaptationId;
        WalkSessionId = walkSessionId;
        Type = type;
        Title = title;
        Explanation = explanation;
        EstimatedAddedMinutes = estimatedAddedMinutes;
        EstimatedAddedDistanceMeters = estimatedAddedDistanceMeters;
        EstimatedNewTotalMinutes = estimatedNewTotalMinutes;
        AffectedStops = affectedStops;
        AddedStops = addedStops;
        RemovedStops = removedStops;
        ReorderedStops = reorderedStops;
        ProposedRoute = proposedRoute;
        ProposedStops = proposedStops;
        RouteRevision = routeRevision;
        ProposedRouteRevision = routeRevision + 1;
        CreatedAtUtc = createdAtUtc;
        ExpiresAtUtc = expiresAtUtc;
        Status = WalkAdaptationStatus.Proposed;
    }

    public string AdaptationId { get; }
    public string WalkSessionId { get; }
    public WalkAdaptationType Type { get; }
    public string Title { get; }
    public string Explanation { get; }
    public int EstimatedAddedMinutes { get; }
    public int EstimatedAddedDistanceMeters { get; }
    public int EstimatedNewTotalMinutes { get; }
    public IReadOnlyList<string> AffectedStops { get; }
    public IReadOnlyList<string> AddedStops { get; }
    public IReadOnlyList<string> RemovedStops { get; }
    public IReadOnlyList<string> ReorderedStops { get; }
    public WalkRoute ProposedRoute { get; }
    public IReadOnlyList<WalkStop> ProposedStops { get; }
    public int RouteRevision { get; }
    public int ProposedRouteRevision { get; }
    public DateTimeOffset CreatedAtUtc { get; }
    public DateTimeOffset ExpiresAtUtc { get; }
    public WalkAdaptationStatus Status { get; private set; }

    public bool IsExpired(DateTimeOffset now) => now >= ExpiresAtUtc;

    public void Accept(DateTimeOffset now)
    {
        if (Status == WalkAdaptationStatus.Applied || Status == WalkAdaptationStatus.Accepted)
        {
            return;
        }

        if (Status != WalkAdaptationStatus.Proposed)
        {
            throw new WalkLifecycleException("Only a Proposed adaptation can be accepted.");
        }

        if (IsExpired(now))
        {
            Status = WalkAdaptationStatus.Expired;
            throw new WalkLifecycleException("Expired adaptations cannot be accepted.");
        }

        Status = WalkAdaptationStatus.Accepted;
    }

    public void Reject()
    {
        if (Status == WalkAdaptationStatus.Rejected)
        {
            return;
        }

        if (Status != WalkAdaptationStatus.Proposed)
        {
            throw new WalkLifecycleException("Only a Proposed adaptation can be rejected.");
        }

        Status = WalkAdaptationStatus.Rejected;
    }

    public void Applied() => Status = WalkAdaptationStatus.Applied;

    public void Fail() => Status = WalkAdaptationStatus.Failed;
}
