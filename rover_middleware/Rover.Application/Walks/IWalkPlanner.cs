using Rover.Domain.Walks;

namespace Rover.Application.Walks;

public interface IWalkPlanner
{
    Task<WalkSession> PlanToPlaceAsync(CreateWalkCommand command, WalkStop requested, CancellationToken ct);
    Task<WalkSession> PlanWalkAsync(CreateWalkCommand command, CancellationToken cancellationToken);
}
