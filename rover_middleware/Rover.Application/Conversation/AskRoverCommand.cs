using Rover.Domain.Walks;

namespace Rover.Application.Conversation;

public sealed record AskRoverCommand(
    string QuestionText,
    string? CurrentStopId,
    GeoLocation? CurrentLocation,
    DateTimeOffset RecordedAtUtc,
    string? ConversationId);
