namespace Rover.Api.Contracts;

public sealed record AskRoverResponse(
    string ConversationId,
    string TurnId,
    string AnswerText,
    DateTimeOffset CreatedAtUtc,
    string? CurrentStopId,
    string Provider,
    string SuggestedAction,
    string? SafetyNotice);
