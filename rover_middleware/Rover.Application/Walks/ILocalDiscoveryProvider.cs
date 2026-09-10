using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public interface ILocalDiscoveryProvider
{
    Task<IReadOnlyList<WalkStop>> FindStopsAsync(CreateWalkCommand command, CancellationToken cancellationToken);
    Task<IReadOnlyList<WalkStop>> FindCandidateStopsAsync(CreateWalkCommand command, CancellationToken cancellationToken, int maximumStops = 30);
}
