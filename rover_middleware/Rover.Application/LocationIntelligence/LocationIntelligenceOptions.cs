namespace Rover.Application.LocationIntelligence;

public sealed class LocationIntelligenceOptions
{
    public bool Enabled { get; set; } = true;
    public int DefaultRadiusMeters { get; set; } = 1500;
    public int MaxRadiusMeters { get; set; } = 5000;
    public int MaximumReturnedPlaces { get; set; } = 12;
    public bool OpenAISynthesisEnabled { get; set; }
    public int HistoricalCacheMinutes { get; set; } = 10080;
    public int PoiCacheMinutes { get; set; } = 240;
    public int WeatherCacheMinutes { get; set; } = 20;
    public int GeneratedStoryCacheMinutes { get; set; } = 10080;
    public int EvidenceFreshnessMinutes { get; set; } = 10080;
    public int SpatialEvidenceFreshnessMinutes { get; set; } = 5;
    public bool PersistentStorageEnabled { get; set; } = true;
    public string PersistentStorageDirectory { get; set; } = "work/location-intelligence";
    public int MaximumStoredStoryPacks { get; set; } = 500;
    public int MaximumStoredEvidenceSets { get; set; } = 1000;
    public int ProviderTimeoutSeconds { get; set; } = 8;
    public double MergeDistanceMeters { get; set; } = 35;
    public double RouteNearDistanceMeters { get; set; } = 120;
    public string UserAgent { get; set; } = "RoverLocationIntelligence/1.0 (local development)";
}

public sealed class LocationProviderOptions
{
    public bool Enabled { get; set; }
    public string? Endpoint { get; set; }
    public string? AccessToken { get; set; }
    public int TimeoutSeconds { get; set; } = 8;
    public int CacheMinutes { get; set; } = 240;
    public int MaximumResults { get; set; } = 10;
}
