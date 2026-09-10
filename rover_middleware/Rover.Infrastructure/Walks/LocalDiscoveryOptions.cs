namespace Rover.Infrastructure.Walks;

public sealed class LocalDiscoveryOptions
{
    public bool Enabled { get; set; }
    public string? AccessToken { get; set; }
    public string Country { get; set; } = "ca";
    public int LimitPerCategory { get; set; } = 6;
    public int MinimumStops { get; set; } = 3;
    public int MaximumStops { get; set; } = 12;
    public double RadiusDegrees { get; set; } = 0.025;
    public int MaximumDistanceMeters { get; set; } = 2_500;
    public TimeSpan Timeout { get; set; } = TimeSpan.FromSeconds(6);
}
