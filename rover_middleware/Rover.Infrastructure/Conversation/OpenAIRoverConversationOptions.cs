namespace Rover.Infrastructure.Conversation;

public sealed class OpenAIRoverConversationOptions
{
    public string? ApiKey { get; set; }
    public string? OrganizationId { get; set; }
    public string? ProjectId { get; set; }
    public string? Model { get; set; }
    public int TimeoutSeconds { get; set; } = 20;
    public bool WebSearchEnabled { get; set; }
}
