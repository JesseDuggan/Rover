namespace Rover.Application.Conversation;

public interface IConversationMemory
{
    IReadOnlyList<ConversationTurn> GetRecentTurns(string conversationId, int limit);

    void AddTurn(string conversationId, ConversationTurn turn, int retentionLimit);
}
