namespace Rover.Infrastructure.LiveContext;

public sealed class GoogleWeatherLiveOptions
{
    public bool Enabled { get; set; }
    public string? ApiKey { get; set; }
    public int TimeoutSeconds { get; set; } = 6;
    public int ForecastHours { get; set; } = 6;
}

public sealed class TicketmasterLiveOptions
{
    public bool Enabled { get; set; }
    public string? ApiKey { get; set; }
    public int TimeoutSeconds { get; set; } = 6;
    public int RadiusKilometers { get; set; } = 25;
    public int MaximumResults { get; set; } = 10;
}

public sealed class OpenAICurrentInformationOptions
{
    public bool Enabled { get; set; }
    public string? ApiKey { get; set; }
    public string? Model { get; set; }
    public int TimeoutSeconds { get; set; } = 12;
    public IReadOnlyList<string> TrustedDomains { get; set; } = Array.Empty<string>();
}
