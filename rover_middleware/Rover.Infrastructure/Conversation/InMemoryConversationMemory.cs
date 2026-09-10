using System.Collections.Concurrent;
using Rover.Application.Conversation;

namespace Rover.Infrastructure.Conversation;

public sealed class InMemoryConversationMemory : IConversationMemory
{
    private readonly ConcurrentDictionary<string, List<ConversationTurn>> _turns = new(StringComparer.OrdinalIgnoreCase);

    public IReadOnlyList<ConversationTurn> GetRecentTurns(string conversationId, int limit)
    {
        if (!_turns.TryGetValue(conversationId, out var turns))
        {
            return Array.Empty<ConversationTurn>();
        }

        lock (turns)
        {
            return turns.TakeLast(Math.Max(0, limit)).ToArray();
        }
    }

    public void AddTurn(string conversationId, ConversationTurn turn, int retentionLimit)
    {
        var turns = _turns.GetOrAdd(conversationId, _ => new List<ConversationTurn>());
        lock (turns)
        {
            turns.Add(turn);
            var overflow = turns.Count - Math.Max(1, retentionLimit);
            if (overflow > 0)
            {
                turns.RemoveRange(0, overflow);
            }
        }
    }
}
