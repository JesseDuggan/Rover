using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public interface IWalkPlanner
{
    Task<WalkSession> PlanWalkAsync(CreateWalkCommand command, CancellationToken cancellationToken);
}
