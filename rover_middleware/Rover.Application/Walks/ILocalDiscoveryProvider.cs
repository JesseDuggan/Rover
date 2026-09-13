using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public interface ILocalDiscoveryProvider
{
    bool RequiresRealPlaces => false;
    async Task<LocalDiscoveryResult> DiscoverForPlanningAsync(CreateWalkCommand command, CancellationToken cancellationToken, int maximumStops)
        => new(await FindCandidateStopsAsync(command, cancellationToken, maximumStops), null);
    Task<IReadOnlyList<WalkStop>> FindStopsAsync(CreateWalkCommand command, CancellationToken cancellationToken);
    Task<IReadOnlyList<WalkStop>> FindCandidateStopsAsync(CreateWalkCommand command, CancellationToken cancellationToken, int maximumStops = 30);
}

public sealed record LocalDiscoveryResult(IReadOnlyList<WalkStop> Stops, string? Diagnostic);
