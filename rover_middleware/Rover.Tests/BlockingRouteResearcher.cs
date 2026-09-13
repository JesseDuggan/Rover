using Rover.Application.Journeys;

internal sealed class BlockingRouteResearcher(CancellationTokenSource? requestCancellation) : ILocalRouteResearcher
{
    public async Task<LocalRouteResearchResult> ResearchAsync(LocalRouteResearchQuery query, CancellationToken cancellationToken)
    {
        requestCancellation?.Cancel();
        await Task.Delay(Timeout.Infinite, cancellationToken);
        return new LocalRouteResearchResult([], null);
    }
}
