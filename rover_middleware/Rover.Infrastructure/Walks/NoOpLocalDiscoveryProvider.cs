using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Walks;

public sealed class NoOpLocalDiscoveryProvider : ILocalDiscoveryProvider
{
    public Task<IReadOnlyList<WalkStop>> FindStopsAsync(CreateWalkCommand command, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult<IReadOnlyList<WalkStop>>(Array.Empty<WalkStop>());
    }

    public Task<IReadOnlyList<WalkStop>> FindCandidateStopsAsync(CreateWalkCommand command, CancellationToken cancellationToken, int maximumStops = 30)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult<IReadOnlyList<WalkStop>>(Array.Empty<WalkStop>());
    }
}
