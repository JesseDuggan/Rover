using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public interface IWalkRouteProvider
{
    string ProviderName { get; }
    Task<WalkRoute> CreateRouteAsync(CreateWalkCommand command, IReadOnlyList<WalkStop> orderedStops, CancellationToken cancellationToken);
}
