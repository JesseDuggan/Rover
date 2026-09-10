namespace Rover.Application.Conversation;

public sealed record ConversationTurn(
    string TurnId,
    string QuestionText,
    string AnswerText,
    DateTimeOffset CreatedAtUtc);
