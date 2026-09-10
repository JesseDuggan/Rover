using Rover.Domain.Walks;

namespace Rover.Application.Adaptations;

public interface IWalkAdaptationRepository
{
    Task AddAsync(WalkAdaptationProposal proposal, CancellationToken cancellationToken);
    Task<WalkAdaptationProposal?> GetAsync(string walkSessionId, string adaptationId, CancellationToken cancellationToken);
    Task UpdateAsync(WalkAdaptationProposal proposal, CancellationToken cancellationToken);
}
