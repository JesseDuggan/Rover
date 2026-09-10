using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public interface IWalkSessionService
{
    Task<WalkSession> CreateAsync(CreateWalkCommand command, CancellationToken cancellationToken);
    Task<WalkSession?> GetAsync(string walkSessionId, CancellationToken cancellationToken);
    Task<IReadOnlyList<WalkStop>?> GetStopsAsync(string walkSessionId, CancellationToken cancellationToken);
    Task<WalkStop?> GetNextStopAsync(string walkSessionId, CancellationToken cancellationToken);
    Task<WalkSession> StartAsync(string walkSessionId, CancellationToken cancellationToken);
    Task<WalkSession> ArriveAtStopAsync(string walkSessionId, string stopId, GeoLocation? currentLocation, CancellationToken cancellationToken);
    Task<LocationUpdateResult> UpdateLocationAsync(string walkSessionId, LocationUpdateCommand command, CancellationToken cancellationToken);
    Task<WalkSession> CompleteAsync(string walkSessionId, CancellationToken cancellationToken);
    Task<WalkSession> CancelAsync(string walkSessionId, CancellationToken cancellationToken);
}
