namespace Rover.Infrastructure.Walks;

public sealed class MapboxRoutingOptions
{
    public string? AccessToken { get; set; }
    public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(8);
}
