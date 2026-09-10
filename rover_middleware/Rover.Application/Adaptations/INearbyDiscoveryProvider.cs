using Rover.Domain.Walks;

namespace Rover.Application.Adaptations;

public interface INearbyDiscoveryProvider
{
    Task<IReadOnlyList<NearbyDiscovery>> FindAsync(
        WalkSession session,
        GeoLocation currentLocation,
        string? interest,
        IReadOnlyCollection<string> dismissedDiscoveryIds,
        CancellationToken cancellationToken);
}
