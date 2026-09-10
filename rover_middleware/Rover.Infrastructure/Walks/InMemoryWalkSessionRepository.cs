using System.Collections.Concurrent;
using Rover.Application.Walks;
using Rover.Domain.Walks;

namespace Rover.Infrastructure.Walks;

public sealed class InMemoryWalkSessionRepository : IWalkSessionRepository
{
    private readonly ConcurrentDictionary<string, WalkSession> _sessions = new(StringComparer.OrdinalIgnoreCase);

    public Task AddAsync(WalkSession session, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        if (!_sessions.TryAdd(session.WalkSessionId, session))
        {
            throw new InvalidOperationException($"Walk session '{session.WalkSessionId}' already exists.");
        }

        return Task.CompletedTask;
    }

    public Task<WalkSession?> GetByIdAsync(string walkSessionId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        _sessions.TryGetValue(walkSessionId, out var session);
        return Task.FromResult(session);
    }

    public Task UpdateAsync(WalkSession session, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();

        _sessions[session.WalkSessionId] = session;
        return Task.CompletedTask;
    }
}
