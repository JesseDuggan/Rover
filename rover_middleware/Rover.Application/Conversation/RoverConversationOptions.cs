namespace Rover.Application.Conversation;

public sealed class RoverConversationOptions
{
    public int MaximumQuestionLength { get; set; } = 500;
    public int MaximumAnswerLength { get; set; } = 900;
    public int RecentTurnLimit { get; set; } = 6;
    public int RetainedTurnLimit { get; set; } = 12;
}
