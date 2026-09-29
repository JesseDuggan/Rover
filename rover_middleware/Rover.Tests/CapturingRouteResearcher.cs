using Rover.Application.Journeys;

internal sealed class CapturingRouteResearcher(Func<LocalRouteResearchQuery, LocalRouteResearchResult> respond) : ILocalRouteResearcher
{
    public Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(respond(query));
    }
}
