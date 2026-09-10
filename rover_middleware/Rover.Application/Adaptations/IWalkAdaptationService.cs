using Rover.Domain.Walks;

namespace Rover.Application.Adaptations;

public interface IWalkAdaptationService
{
    Task<WalkAdaptationProposal> EvaluateAsync(string walkSessionId, WalkAdaptationCommand command, CancellationToken cancellationToken);
    Task<WalkAdaptationProposal?> GetAsync(string walkSessionId, string adaptationId, CancellationToken cancellationToken);
    Task<WalkSession> AcceptAsync(string walkSessionId, string adaptationId, int routeRevision, CancellationToken cancellationToken);
    Task<WalkAdaptationProposal> RejectAsync(string walkSessionId, string adaptationId, CancellationToken cancellationToken);
}
