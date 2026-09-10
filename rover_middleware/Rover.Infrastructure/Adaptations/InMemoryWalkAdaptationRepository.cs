using System.Collections.Concurrent;
using Rover.Application.Adaptations;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Adaptations;

public sealed class InMemoryWalkAdaptationRepository : IWalkAdaptationRepository
{
    private readonly ConcurrentDictionary<string, WalkAdaptationProposal> _proposals = new(StringComparer.OrdinalIgnoreCase);

    public Task AddAsync(WalkAdaptationProposal proposal, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _proposals[$"{proposal.WalkSessionId}:{proposal.AdaptationId}"] = proposal;
        return Task.CompletedTask;
    }

    public Task<WalkAdaptationProposal?> GetAsync(string walkSessionId, string adaptationId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _proposals.TryGetValue($"{walkSessionId}:{adaptationId}", out var proposal);
        return Task.FromResult(proposal);
    }

    public Task UpdateAsync(WalkAdaptationProposal proposal, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        _proposals[$"{proposal.WalkSessionId}:{proposal.AdaptationId}"] = proposal;
        return Task.CompletedTask;
    }
}
