using Rover.Domain.Walks;
using Rover.Application.Walks;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Rover.Application.LocationIntelligence;

public sealed class OntarioFieldTestOptions
{
    public bool Enabled { get; set; }
    public bool AllowAllBetaTesters { get; set; }
    public string ReportDirectory { get; set; } = "work/ontario-field-tests";
    public int RetentionDays { get; set; } = 90;
    public Dictionary<string, OntarioMarketOptions> Markets { get; set; } = new(StringComparer.OrdinalIgnoreCase);

    public KeyValuePair<string, OntarioMarketOptions>? Match(Guid? profileId, GeoLocation location)
    {
        if (!Enabled || !IsParticipant(profileId)) return null;
        // Enrollment is not a geographic lock. A tester can visit any enabled market.
        return Markets.Where(market => market.Value.Enabled && market.Value.Contains(location))
            .OrderBy(market => market.Value.Center is { } center ? RouteMath.DistanceMeters(center, location) : 0)
            .ThenBy(market => market.Value.GeographicProfileId, StringComparer.Ordinal)
            .Select(market => (KeyValuePair<string, OntarioMarketOptions>?)market).FirstOrDefault();
    }

    public KeyValuePair<string, OntarioMarketOptions>? ForJourney(WalkSession session)
    {
        if (!Enabled || !IsParticipant(session.ProfileId)) return null;
        if (session.GeographicProfileId is null) return Match(session.ProfileId, session.StartingLocation);
        return Markets.Where(market => market.Value.Enabled && market.Value.GeographicProfileId == session.GeographicProfileId)
            .Select(market => (KeyValuePair<string, OntarioMarketOptions>?)market).FirstOrDefault();
    }

    private bool IsParticipant(Guid? profileId) => AllowAllBetaTesters || profileId is { } id && id != Guid.Empty
        && Markets.Values.Any(market => market.Enabled && market.TesterProfileIds.Contains(id));

    public void Validate()
    {
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var market in Markets.Values)
            if (!Regex.IsMatch(market.GeographicProfileId, "^[A-Z][A-Z0-9-]{0,63}$")
                || !ids.Add(market.GeographicProfileId) || string.IsNullOrWhiteSpace(market.Region)
                || !market.HasValidGeography || market.MaximumStopDistanceMeters is < 100 or > 3000)
                throw new InvalidOperationException("Ontario geographic profiles require unique stable IDs, a region, valid geography, and a stop radius between 100 and 3000 metres.");
    }
}

public sealed class OntarioMarketOptions
{
    public bool Enabled { get; set; }
    public string GeographicProfileId { get; set; } = "";
    public string Region { get; set; } = "";
    public GeoLocation? Center { get; set; }
    public string City { get; set; } = "";
    public Guid[] TesterProfileIds { get; set; } = [];
    public OntarioTestArea[] Areas { get; set; } = [];
    public OntarioMunicipalDataset[] Datasets { get; set; } = [];
    public bool IncludeExistingHeritageSources { get; set; } = true;
    public int SearchRadiusMeters { get; set; } = 1200;
    public int MaximumStopDistanceMeters { get; set; } = 2000;
    public int MaximumPlaces { get; set; } = 30;
    public bool HasValidGeography => SearchRadiusMeters is >= 100 and <= 10000
        && (Center is { } center ? ValidPoint(center) : Areas.Length > 0 && Areas.All(area => area.IsValid));
    public bool Contains(GeoLocation point) => HasValidGeography && ValidPoint(point)
        && (Center is { } center ? RouteMath.DistanceMeters(center, point) <= SearchRadiusMeters : Areas.Any(area => area.Contains(point)));
    private static bool ValidPoint(GeoLocation point) => double.IsFinite(point.Latitude) && double.IsFinite(point.Longitude)
        && point.Latitude is >= -90 and <= 90 && point.Longitude is >= -180 and <= 180;
}

public sealed class OntarioTestArea
{
    public string Name { get; set; } = "";
    public double West { get; set; }
    public double South { get; set; }
    public double East { get; set; }
    public double North { get; set; }
    public bool IsValid => double.IsFinite(West) && double.IsFinite(South) && double.IsFinite(East)
        && double.IsFinite(North) && West >= -180 && East <= 180 && South >= -90 && North <= 90
        && West < East && South < North && East - West <= .1 && North - South <= .1;
    public bool Contains(GeoLocation point) => IsValid && double.IsFinite(point.Latitude) && double.IsFinite(point.Longitude)
        && point.Longitude >= West && point.Longitude <= East && point.Latitude >= South && point.Latitude <= North;
}

public sealed class OntarioMunicipalDataset
{
    public bool Enabled { get; set; }
    public string Id { get; set; } = "";
    public string Endpoint { get; set; } = "";
    public string CatalogUrl { get; set; } = "";
    public string LicenseUrl { get; set; } = "";
    public string Attribution { get; set; } = "";
    public string NameField { get; set; } = "";
    public string[] AddressFields { get; set; } = [];
    public string StatusField { get; set; } = "";
    public string DescriptionField { get; set; } = "";
    public string Where { get; set; } = "1=1";
    public int CacheMinutes { get; set; } = 1440;
    public int MaximumRecords { get; set; } = 1000;
}

public sealed record OntarioFieldTestFeedback(Guid ProfileId, int StoryAccuracy, int StoryRelevance,
    int? VoiceQuality, int RouteQuality, string NarrationResult, string? Comments)
{
    [JsonIgnore]
    public bool IsValid => ProfileId != Guid.Empty
        && new[] { StoryAccuracy, StoryRelevance, RouteQuality }.All(rating => rating is >= 1 and <= 5)
        && (VoiceQuality is >= 1 and <= 5 || VoiceQuality is null && NarrationResult == "not-tested")
        && NarrationResult is "not-tested" or "played" or "failed" or "interrupted" or "device-fallback"
        && (Comments?.Length ?? 0) <= 1000;
}

// Operational events contain counts and timings, not precise tracks, audio, or API keys.
public sealed record OntarioFieldTestEvent(string Market, string Kind, string Outcome,
    long ElapsedMilliseconds = 0, int Discovered = 0, int Evidence = 0, int Stories = 0,
    int Excluded = 0, int Duplicates = 0, string? Source = null, string? WalkSessionId = null,
    OntarioFieldTestFeedback? Feedback = null, string? GeographicProfileId = null);

public interface IOntarioFieldTestRecorder
{
    void Record(OntarioFieldTestEvent entry);
}
