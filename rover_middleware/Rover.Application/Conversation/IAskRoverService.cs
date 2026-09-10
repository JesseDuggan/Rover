namespace Rover.Application.Conversation;

public interface IAskRoverService
{
    Task<AskRoverResult> AskAsync(
        string walkSessionId,
        AskRoverCommand command,
        CancellationToken cancellationToken);
}
