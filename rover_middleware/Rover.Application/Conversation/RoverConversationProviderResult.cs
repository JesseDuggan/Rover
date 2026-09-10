namespace Rover.Application.Conversation;

public sealed record RoverConversationProviderResult(
    string AnswerText,
    string SuggestedAction = "Informational",
    string? SafetyNotice = null);
