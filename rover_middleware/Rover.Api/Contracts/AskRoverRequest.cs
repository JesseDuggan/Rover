namespace Rover.Api.Contracts;

public sealed record AskRoverRequest(
    string? QuestionText,
    string? CurrentStopId,
    double? Latitude,
    double? Longitude,
    DateTimeOffset? RecordedAtUtc,
    string? ConversationId);
