namespace Rover.Application.LocationIntelligence;

public interface ISelectedLocationProvider
{
    Task<LocationPlace?> FindSelectedAsync(string canonicalId, CancellationToken cancellationToken);
}
