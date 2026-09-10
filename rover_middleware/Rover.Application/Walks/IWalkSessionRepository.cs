using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public interface IWalkSessionRepository
{
    Task AddAsync(WalkSession session, CancellationToken cancellationToken);
    Task<WalkSession?> GetByIdAsync(string walkSessionId, CancellationToken cancellationToken);
    Task UpdateAsync(WalkSession session, CancellationToken cancellationToken);
}
