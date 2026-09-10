namespace Rover.Application.Conversation;

public sealed record AskRoverResult(
    string ConversationId,
    string TurnId,
    string AnswerText,
    DateTimeOffset CreatedAtUtc,
    string? CurrentStopId,
    string Provider,
    string SuggestedAction,
    string? SafetyNotice);
