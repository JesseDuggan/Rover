using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Rover.Application.Beta;
using Rover.Application.Speech;
using Rover.Infrastructure.Storage;

namespace Rover.Infrastructure.Beta;

public sealed class BetaConfigurationService : IBetaConfigurationService
{
    private readonly IConfiguration _configuration;
    private readonly IHostEnvironment _environment;
    private readonly ElevenLabsSpeechOptions _speechOptions;

    public BetaConfigurationService(IConfiguration configuration, IHostEnvironment environment, ElevenLabsSpeechOptions speechOptions)
    {
        _configuration = configuration;
        _environment = environment;
        _speechOptions = speechOptions;
    }

    public BetaConfigurationStatus GetStatus()
    {
        var isDevelopment = _environment.IsDevelopment();
        var isTesting = _environment.IsEnvironment("Testing");
        var isBeta = _environment.IsEnvironment("Beta") || _environment.IsStaging();
        var warnings = new List<string>();
        var storageMode = Environment.GetEnvironmentVariable("ROVER_STORAGE_MODE") ?? _configuration["Rover:Storage:Mode"] ?? "InMemory";
        var routingMode = Environment.GetEnvironmentVariable("ROVER_ROUTING_MODE") ?? _configuration["Rover:Routing:Mode"] ?? "Mock";
        var googleRoutesKey = Environment.GetEnvironmentVariable("GOOGLE_ROUTES_API_KEY")
            ?? Environment.GetEnvironmentVariable("GOOGLE_PLACES_API_KEY")
            ?? _configuration["Rover:Routing:Google:ApiKey"];

        if (isBeta)
        {
            WarnIf(isDevelopment, "Development environment cannot be used for private beta.");
            WarnIf(storageMode.Equals(StorageMode.InMemory.ToString(), StringComparison.OrdinalIgnoreCase), "Beta must use durable storage.");
            WarnIf(!routingMode.Equals("Google", StringComparison.OrdinalIgnoreCase), "Beta must use Google pedestrian routing.");
            WarnIf(string.IsNullOrWhiteSpace(googleRoutesKey), "Beta requires server-side Google Routes configuration.");
            WarnIf(!_speechOptions.Enabled || string.IsNullOrWhiteSpace(_speechOptions.ApiKey), "Beta requires server-side ElevenLabs configuration or explicit fallback approval.");
        }

        return new BetaConfigurationStatus(
            _environment.EnvironmentName,
            _configuration["Rover:Build:Version"] ?? "1.0.0",
            _configuration["Rover:Build:Number"] ?? "1",
            isBeta,
            isDevelopment || isTesting,
            isDevelopment || isTesting,
            isDevelopment || isTesting,
            isBeta || _environment.IsProduction(),
            !ContainsInlineSecret(_configuration["ElevenLabs:ApiKey"]) && !ContainsInlineSecret(_configuration["Rover:Routing:Google:ApiKey"]),
            !string.IsNullOrWhiteSpace(googleRoutesKey),
            _speechOptions.Enabled && !string.IsNullOrWhiteSpace(_speechOptions.ApiKey) && !string.IsNullOrWhiteSpace(_speechOptions.VoiceId),
            warnings);

        void WarnIf(bool condition, string warning)
        {
            if (condition)
            {
                warnings.Add(warning);
            }
        }
    }

    private static bool ContainsInlineSecret(string? value)
    {
        return !string.IsNullOrWhiteSpace(value) && !value.StartsWith("REPLACE", StringComparison.OrdinalIgnoreCase);
    }
}
