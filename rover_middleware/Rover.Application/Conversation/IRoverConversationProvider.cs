namespace Rover.Application.Conversation;

public interface IRoverConversationProvider
{
    string Name { get; }

    Task<RoverConversationProviderResult> AnswerAsync(
        RoverConversationContext context,
        string questionText,
        CancellationToken cancellationToken);
}
