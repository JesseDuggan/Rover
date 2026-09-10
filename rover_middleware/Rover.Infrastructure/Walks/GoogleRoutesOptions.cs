namespace Rover.Infrastructure.Walks;

public sealed class GoogleRoutesOptions
{
    public string? ApiKey { get; set; }
    public string Endpoint { get; set; } = "https://routes.googleapis.com/directions/v2:computeRoutes";
    public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(8);
}
